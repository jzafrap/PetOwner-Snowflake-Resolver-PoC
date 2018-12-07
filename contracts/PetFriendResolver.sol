pragma solidity ^0.5.0;
pragma experimental ABIEncoderV2;

import "./SnowflakeResolver.sol";
import "./SnowflakeInterface.sol";
import "./stringSet.sol";
import "./SafeMath.sol";
import "./IdentityRegistryInterface.sol";


contract PetFriendResolver is SnowflakeResolver {
    //Revision history
    //v0.3:
    //   -add method unclaimLostReport => changes report status from Found to Pending
    //   -remove PetChanged event 
    //   -add modifier _lostReportActive  
    //   -add getOwner method
    //v0.4:
    //   -add method updateOwner => updates owners data
    //v0.5:
    //   -add method getPetOwner(string petId)
     //v0.51
    //   -add ownerId to getPetOwner(string petId)
    //v0.52 private modifier to all state vars, to disable public methods on compile
    //v0.53 
    //   -canUnclaim modifier for unclaim verify
    //v.6:
    //   -extraParams to initialize state
    
    
    using stringSet for stringSet._stringSet;
    using SafeMath for uint;
    
    //Owner Fields
    struct Owner{
        //string snowflakeId; //PK
        uint ein; //PK
        string contactName;
        string contactData;
        string[] petIds;
    }

 
    //Pet fields
    struct Pet {
        uint ownerId;
        string petId; //PK
        string petType;
        string name;
        string desc;
        string imgUrl;
    }
    
   //Pet Reports
    struct LostReport{
        string petId; //PK
        Status status;
        string sceneDesc;
        uint reward;
        uint claimerHydroId;
    }

    //one hydro is represented as 1000000000000000000
    uint private signUpFee = uint(1).mul(10**18);

    enum Status {None, Pending, Found, Removed, Rewarded}
    
     //pets registry by petId(PK)
    mapping (string => Pet)  private pets; //
    
    //owners registry by ein
    mapping (uint => Owner) private owners;
    
    //lost report of a petId
    mapping (string => LostReport) private lostReports; 
    
    //all active lost report keys; used to list in frontend
    stringSet._stringSet private  lostReportKeys;
    
     
     //Events
  
    
    //when lost report changes: reports, modifies, claimed, closed...
    //to be used to list an historic of pet incidences
    event LostReportChanged(
        bytes32 indexed hashedPetId,
        string petId, 
        uint date,
        Status status,
        string sceneDesc,
        uint reward,
        uint claimerEin
    );
    
    function  emitEvent (  string memory petId, 
        uint date,
        Status status,
        string memory sceneDesc,
        uint reward,
        uint claimerEin) private{
            bytes32 hashedPetId = keccak256(abi.encode(petId));
        emit LostReportChanged(hashedPetId,petId, date,status,sceneDesc,reward,claimerEin);
        }
    
    
    //modifiers
     modifier _onlyOwner(uint ein)
     {   
         SnowflakeInterface snowflake = SnowflakeInterface(snowflakeAddress);
         IdentityRegistryInterface identityRegistry = IdentityRegistryInterface(snowflake.identityRegistryAddress());
         require(identityRegistry.isAssociatedAddressFor(ein,msg.sender));
         _;
     }
     
     
     modifier _lostReportActive(string memory petId)
     {
        //require(bytes(pets[petId].desc).length >0,"No pet exists with that petId");
        require(lostReportKeys.contains(petId));
        _;
     }
    
    modifier _uniquePetId(string memory petId){
        //require(pets[petId].length==0);
         require(bytes(pets[petId].petId).length ==0,"No pet exists with that petId");
        _;
    } 
    
    
     modifier _canUnclaim(string memory petId)
     {   
        SnowflakeInterface snowflake = SnowflakeInterface(snowflakeAddress);
        IdentityRegistryInterface identityRegistry = IdentityRegistryInterface(snowflake.identityRegistryAddress());
        uint ownerId = pets[petId].ownerId;
        uint claimerHydroId = lostReports[petId].claimerHydroId;
        require(
            (identityRegistry.getEIN(msg.sender) == ownerId)
            ||
           (identityRegistry.getEIN(msg.sender) == claimerHydroId)
        );
         _;
     }
     
    constructor (address snowflakeAddress)
        SnowflakeResolver("Pet Owner Resolver v0.6 - get your Pet Friend membership", "Become a member of Pet Friends community and register your pets!", snowflakeAddress, true, false) public
    {  }
    
       // implement signup function
    function onAddition(uint ein, uint, bytes memory extraData) public senderIsSnowflake() returns (bool) {
        SnowflakeInterface snowflake = SnowflakeInterface(snowflakeAddress);
        snowflake.withdrawSnowflakeBalanceFrom(ein, owner(), signUpFee);

      	//3. update the mapping owners
      	 (string memory contactName, string memory contactData) = abi.decode(extraData, (string, string));
		owners[ein].contactName = contactName;
		owners[ein].contactData = contactData;

       // emit StatusSignUp(ein);
        return true;
    }
     function onRemoval(uint, bytes memory) public senderIsSnowflake() returns (bool) {
         return true;
     }

     //event StatusSignUp(uint ein);
    
    function getOwner(uint ownerId)public view returns (string memory contactName, string memory contactData ){
        return( owners[ownerId].contactName,
                owners[ownerId].contactData)  ;  
    }
    
    function getPetOwner(string memory petId)  public view returns (uint ownerId,string memory contactName, string memory contactData ){
        return(
            pets[petId].ownerId,
            owners[pets[petId].ownerId].contactName,
            owners[pets[petId].ownerId].contactData);
        
    }
    
    function updateOwner(uint ownerId, string memory contactName, string memory contactData) 
        public
        _onlyOwner(ownerId)
        returns (bool success)
        {
            owners[ownerId].contactName = contactName;
            owners[ownerId].contactData = contactData;  
            return(true);
    }
    
    function getOwnerPets(uint ownerId) public view returns(string[] memory){
           return owners[ownerId].petIds;
    }
    
      
     //get pet data from petId
    function getPet(string memory petId) public view returns (string memory petType, string memory name, string memory desc, string memory imgUrl) 
    {
       return( 
            pets[petId].petType, 
            pets[petId].name, 
            pets[petId].desc, 
            pets[petId].imgUrl
       	);
    }

    //The owner creates a new pet
    function addPet(uint ownerId, string memory petId, string memory petType, string memory name, string memory desc, string memory imgUrl) 
        public 
        _onlyOwner(ownerId) //0. sender must be ownerId 
        _uniquePetId(petId) //2. verify   petId not repeated
        returns (bool success)  
    {
      	//1. verify all required fields
		 //require(bytes(pets[petId].desc).length == 0,"A pet already registered with this petId");
		//3. update the data
		
		pets[petId].petId =petId;
		pets[petId].petType = petType;
	    pets[petId].name=name;
		pets[petId].desc=desc;
		pets[petId].imgUrl=imgUrl;
		pets[petId].ownerId = ownerId;
		
		//4. register pet ownership
		owners[ownerId].petIds.push(petId);

		return (true);
    }
    
     function updatePet(uint ownerId, string memory petId, string memory petType,  string memory name, string memory desc, string memory imgUrl) public _onlyOwner(ownerId) returns (bool success)  
    {
        //0. sender must be ownerId
      	//1. verify all required fields
		//2. verify   petId already exists
			 require(bytes(pets[petId].desc).length >0,"No pet exists with that petId");
		//3. update the data
			//pets[hydroId].petId = petId;
			pets[petId].petType = petType;
			pets[petId].name=name;
			pets[petId].desc=desc;
			pets[petId].imgUrl=imgUrl;
		
			return (true);
		//}else{
		//	return (false);
		//}
    }

    //Returning key array is possible to query by key element
    function getAllLostReportKeys() public view returns(string[] memory){
        return lostReportKeys.members;
    }
    
    function getLostReport(string memory petId)  public view returns(
        Status status,
        string memory sceneDesc,
        uint reward,
        uint claimerHydroId
        ){
        return (
            lostReports[petId].status,
            lostReports[petId].sceneDesc,
            lostReports[petId].reward,
            lostReports[petId].claimerHydroId
        );
    }
    
    

    //new LostReport
    function putLostReport(uint ownerId, string memory petId, string memory sceneDesc, uint reward ) public _onlyOwner(ownerId) returns (bool){
        //1. report dont exists
        require(bytes(lostReports[petId].sceneDesc).length==0,"Lost Report already exists.");
        //2. create new struct, assign to storate mapping
        //persist on storage
        lostReports[petId].sceneDesc = sceneDesc;
        lostReports[petId].reward = reward;
        lostReports[petId].status = Status.Pending;

        lostReportKeys.insert(petId); //can exists?
        //emit LostReportChanged(keccak256(abi.encode(petId)),petId, now,lostReports[petId].status,lostReports[petId].sceneDesc,lostReports[petId].reward,lostReports[petId].claimerHydroId);
        emitEvent(petId, now,lostReports[petId].status,lostReports[petId].sceneDesc,lostReports[petId].reward,lostReports[petId].claimerHydroId);
        
      
        return true;
    }
    
    
    //new LostReport
    function updateLostReport(uint ownerId, string memory petId, string memory sceneDesc, uint reward ) public _onlyOwner(ownerId) returns (bool){
        //1. report dont exists
        require(bytes(lostReports[petId].sceneDesc).length>0,"Lost Report don't exists.");
        //2. create new struct, assign to storate mapping
        //persist on storage
        lostReports[petId].sceneDesc = sceneDesc;
        lostReports[petId].reward = reward;
        lostReports[petId].status = Status.Pending;
         
        lostReportKeys.insert(petId); //can exists?
        emitEvent(petId, now,lostReports[petId].status,lostReports[petId].sceneDesc,lostReports[petId].reward,lostReports[petId].claimerHydroId);
        
      
        return true;
    }
 
    //owner can remove a lost report, when he finds the pen again, for example, o is found dead, etc.
    function removeLostReport(uint ownerId, string memory petId) public _onlyOwner(ownerId) returns (bool){
        //petId must have a report
        require(bytes(lostReports[petId].sceneDesc).length > 0,"Active LostReport doesn't exists");
        lostReports[petId].status = Status.Removed;
       
       
        emitEvent(petId, now,lostReports[petId].status,lostReports[petId].sceneDesc,lostReports[petId].reward,lostReports[petId].claimerHydroId);
        
        //delete all struct elements for hydroId
        delete lostReports[petId];
        //delete key
        lostReportKeys.remove(petId);
        
       
        return true;
    }
    
    //somebody claims the pet found
    function claimLostReport(string memory petId, uint claimerHydroId /*,string notesOnClaim*/) public returns (bool){
       //require(hydroId != claimerHydroId, "Claimer can't be the pet owner, use removeLostReportByOwner instead.");
        require(bytes(lostReports[petId].sceneDesc).length > 0,"Lost Report doesn't exist");
        require(lostReports[petId].status == Status.Pending, "Lost Report is not pending");
        //change status and snowflakeDescription
        lostReports[petId].claimerHydroId =claimerHydroId;
        lostReports[petId].status =Status.Found;
       
        //lostReports[hydroId].notesOnClaim = notesOnClaim;
        emitEvent(petId, now,lostReports[petId].status,lostReports[petId].sceneDesc,lostReports[petId].reward,lostReports[petId].claimerHydroId);
        
      
        return true;
    }
    
    
    //unclaim previos claimed report: only can unclaim the owner or the claimer or pet owner   
    function unclaimLostReport(string memory petId) public _canUnclaim (petId) returns (bool){
        require(bytes(lostReports[petId].sceneDesc).length > 0,"Lost Report doesn't exist");
        require(lostReports[petId].status == Status.Found, "Lost Report is not claimed");
       
        //change status and snowflakeDescription
        lostReports[petId].claimerHydroId =0;
        lostReports[petId].status =Status.Pending;
       
        //lostReports[hydroId].notesOnClaim = notesOnClaim;
        emitEvent(petId, now,lostReports[petId].status,lostReports[petId].sceneDesc,lostReports[petId].reward,lostReports[petId].claimerHydroId);
        
      
        return true;
    }
    
    
    function confirmReward(uint ownerId, string memory petId) public _onlyOwner(ownerId) returns (bool){
        //sender must be pet owner
        
        //report must exists
        require(bytes(lostReports[petId].sceneDesc).length > 0,"LosReport doesn't exists");
        //report status must be found
        require(lostReports[petId].status == Status.Found, "The state of Lost Report is not found!");
        
        SnowflakeInterface snowflake = SnowflakeInterface(snowflakeAddress);
        //require(snowflake.snowflakeBalance(ownerId) >= lostReports[petId].reward.mul(10**18));
        
        uint  claimerHydroId = lostReports[petId].claimerHydroId;
        uint  reward = lostReports[petId].reward;
        //change state to Closed
        lostReports[petId].status = Status.Rewarded;
       
        //as a good pattern, always call other contracts the last thing
        //make the transfer
        snowflake.transferSnowflakeBalanceFrom(ownerId,  claimerHydroId, reward.mul(10**18));
        
        //LostReportChanged event
        emitEvent(petId, now,lostReports[petId].status,lostReports[petId].sceneDesc,lostReports[petId].reward,lostReports[petId].claimerHydroId);
        
       
         
         //delete all struct elements for hydroOwnerId
        delete lostReports[petId];
        //delete key
        lostReportKeys.remove(petId);
        
       
        return true;
    }


}
