pragma solidity ^0.4.24;
pragma experimental ABIEncoderV2;

import "./SnowflakeResolver.sol";
import "./stringSet.sol";
import "./SafeMath.sol";


interface Snowflake {
    function whitelistResolver(address resolver) external;
    function withdrawSnowflakeBalanceFrom(string hydroIdFrom, address to, uint amount) external;
    function getHydroId(address _address) external returns (string hydroId);
    function transferSnowflakeBalanceFrom(string hydroIdFrom, string hydroIdTo, uint amount) external;
    function snowflakeBalance(string hydroId) external view returns (uint);
}

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
    
    
    using stringSet for stringSet._stringSet;
    using SafeMath for uint;
    
    //Owner Fields
    struct Owner{
        string snowflakeId; //PK
        string contactName;
        string contactData;
        string[] petIds;
    }

 
    //Pet fields
    struct Pet {
        string ownerId;
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
        string claimerHydroId;
    }

    //one hydro is represented as 1000000000000000000
    uint signUpFee = uint(1).mul(10**18);

    enum Status {None, Pending, Found, Removed, Rewarded}
    
     //pets registry by petId(PK)
    mapping (string => Pet)  private pets; //
    
    //owners registry by snowflakeId
    mapping (string => Owner) private owners;
    
    //lost report of a petId
    mapping (string => LostReport) private lostReports; 
    
    //all active lost report keys; used to list in frontend
    stringSet._stringSet private  lostReportKeys;
     
     //Events
  
    
    //when lost report changes: reports, modifies, claimed, closed...
    //to be used to list an historic of pet incidences
    event LostReportChanged(
        string indexed petId, 
        uint date,
        LostReport lostReport
    );
    
    //modifiers
     modifier _onlyOwner(string ownerId)
     {   
         Snowflake snowflake = Snowflake(snowflakeAddress);
         string memory senderSnowflake = snowflake.getHydroId(msg.sender);
         //require(senderSnowflake == ownerId);
         require(keccak256(senderSnowflake) == keccak256(ownerId));
         _;
     }
     
     modifier _lostReportActive(string petId)
     {
        //require(bytes(pets[petId].desc).length >0,"No pet exists with that petId");
        require(lostReportKeys.contains(petId));
        _;
     }
    
    modifier _uniquePetId(string petId){
        //require(pets[petId].length==0);
         require(bytes(pets[petId].petId).length ==0,"No pet exists with that petId");
        _;
    } 
    
     modifier _canUnclaim(string petId)
     {   
         Snowflake snowflake = Snowflake(snowflakeAddress);
         string memory senderSnowflake = snowflake.getHydroId(msg.sender);
         //require(senderSnowflake == ownerId);
         require(
             (keccak256(senderSnowflake) == keccak256(pets[petId].ownerId))
             || 
             (keccak256(senderSnowflake) == keccak256(lostReports[petId].claimerHydroId))
             ,"unclaimer must be owner or claimer");
         _;
     }
     
    constructor () public {
        snowflakeAddress = 0x8b8B004aBF1eE64e23D6088B73873898d8408A6d; //rinkeby address of snowflake contract
		snowflakeName = "Pet Owner Resolver v0.5 - get your Pet Friend membership";
        snowflakeDescription = "Become a member of Pet Friends community and register your pets!";
		//setSnowflakeAddress(snowflakeAddress);

        callOnSignUp = true;
		Snowflake snowflake = Snowflake(snowflakeAddress);
        snowflake.whitelistResolver(address(this));
        
    }

    // implement signup function
    function onSignUp(string hydroId, uint allowance) 
        public 
        senderIsSnowflake()  
        returns (bool) 
        {
        require(allowance >= signUpFee, "Must set an allowance of at least 1 HYDRO.");
        Snowflake snowflake = Snowflake(snowflakeAddress);
        snowflake.withdrawSnowflakeBalanceFrom(hydroId, owner, signUpFee);
        
		//3. update the mapping owners
		owners[hydroId].contactName = "Set owner's name";
		owners[hydroId].contactData = "Set owner's public contact info";

        return true;
    }
    
    function getOwner(string hydroId)public view returns (string contactName, string contactData ){
        return( owners[hydroId].contactName,
                owners[hydroId].contactData)  ;  
    }
    
    function getPetOwner(string petId)  public view returns (string ownerId,string contactName, string contactData ){
        return(
            pets[petId].ownerId,
            owners[pets[petId].ownerId].contactName,
            owners[pets[petId].ownerId].contactData);
        
    }
    
    function updateOwner(string hydroId, string contactName, string contactData) 
        public
        _onlyOwner(hydroId)
        returns (bool success)
        {
            owners[hydroId].contactName = contactName;
            owners[hydroId].contactData = contactData;  
            return(true);
    }
    
    
    function getOwnerPets(string ownerId) public view returns(string[]){
        return owners[ownerId].petIds;    
    }
    
      
     //get pet data from petId
    function getPet(string petId) public view returns (string petType, string name, string desc, string imgUrl) 
    {
       return( 
            pets[petId].petType, 
            pets[petId].name, 
            pets[petId].desc, 
            pets[petId].imgUrl
       	);
    }

    //The owner creates a new pet
    function addPet(string ownerId, string petId, string petType, string name, string desc, string imgUrl) 
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
    
     function updatePet(string ownerId, string petId, string petType,  string name, string desc, string imgUrl) public _onlyOwner(ownerId) returns (bool success)  
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
    function getAllLostReportKeys() public view returns(string[]){
        return lostReportKeys.members;
    }
    
    function getLostReport(string petId)  public view returns(
        Status status,
        string sceneDesc,
        uint reward,
        string claimerHydroId
        ){
        return (
            lostReports[petId].status,
            lostReports[petId].sceneDesc,
            lostReports[petId].reward,
            lostReports[petId].claimerHydroId
        );
    }
    
    

    //new LostReport
    function putLostReport(string ownerId, string petId, string sceneDesc, uint reward ) public _onlyOwner(ownerId) returns (bool){
        //1. report dont exists
        require(bytes(lostReports[petId].sceneDesc).length==0,"Lost Report already exists.");
        //2. create new struct, assign to storate mapping
        //persist on storage
        lostReports[petId].sceneDesc = sceneDesc;
        lostReports[petId].reward = reward;
        lostReports[petId].status = Status.Pending;

        lostReportKeys.insert(petId); //can exists?
        emit LostReportChanged(petId,now, lostReports[petId]);
        return true;
    }
    
    
    //new LostReport
    function updateLostReport(string ownerId, string petId, string sceneDesc, uint reward ) public _onlyOwner(ownerId) returns (bool){
        //1. report dont exists
        require(bytes(lostReports[petId].sceneDesc).length>0,"Lost Report don't exists.");
        //2. create new struct, assign to storate mapping
        //persist on storage
        lostReports[petId].sceneDesc = sceneDesc;
        lostReports[petId].reward = reward;
        lostReports[petId].status = Status.Pending;
         
        lostReportKeys.insert(petId); //can exists?
        emit LostReportChanged(petId,now, lostReports[petId]);
        return true;
    }
 
    //owner can remove a lost report, when he finds the pen again, for example, o is found dead, etc.
    function removeLostReport(string ownerId, string petId) public _onlyOwner(ownerId) returns (bool){
        //petId must have a report
        require(bytes(lostReports[petId].sceneDesc).length > 0,"Active LostReport doesn't exists");
        lostReports[petId].status = Status.Removed;
       
       
         emit LostReportChanged(petId, now,lostReports[petId]);
        //delete all struct elements for hydroId
        delete lostReports[petId];
        //delete key
        lostReportKeys.remove(petId);
        
       
        return true;
    }
    
    //somebody claims the pet found
    function claimLostReport(string petId, string claimerHydroId /*,string notesOnClaim*/) public returns (bool){
       //require(hydroId != claimerHydroId, "Claimer can't be the pet owner, use removeLostReportByOwner instead.");
        require(bytes(lostReports[petId].sceneDesc).length > 0,"Lost Report doesn't exist");
        require(lostReports[petId].status == Status.Pending, "Lost Report is not pending");
        //change status and snowflakeDescription
        lostReports[petId].claimerHydroId =claimerHydroId;
        lostReports[petId].status =Status.Found;
       
        //lostReports[hydroId].notesOnClaim = notesOnClaim;
        emit LostReportChanged(petId,now,lostReports[petId]);
        return true;
    }
    
    //unclaim previos claimed report: only can unclaim the owner or the claimer or pet owner   
    function unclaimLostReport(string petId) public _canUnclaim (petId) returns (bool){
        require(bytes(lostReports[petId].sceneDesc).length > 0,"Lost Report doesn't exist");
        require(lostReports[petId].status == Status.Found, "Lost Report is not claimed");
       
        //change status and snowflakeDescription
        lostReports[petId].claimerHydroId ='';
        lostReports[petId].status =Status.Pending;
       
        //lostReports[hydroId].notesOnClaim = notesOnClaim;
        emit LostReportChanged(petId,now,lostReports[petId]);
        return true;
    }
    
    function confirmReward(string ownerId, string petId) public _onlyOwner(ownerId) returns (bool){
        //sender must be pet owner
        
        //report must exists
        require(bytes(lostReports[petId].sceneDesc).length > 0,"LosReport doesn't exists");
        //report status must be found
        require(lostReports[petId].status == Status.Found, "The state of Lost Report is not found!");
        
        Snowflake snowflake = Snowflake(snowflakeAddress);
        require(snowflake.snowflakeBalance(ownerId) >= lostReports[petId].reward.mul(10**18));
        
        string memory claimerHydroId = lostReports[petId].claimerHydroId;
        uint  reward = lostReports[petId].reward;
        //change state to Closed
        lostReports[petId].status = Status.Rewarded;
       
       
        //LostReportChanged event
        emit LostReportChanged(petId, now,lostReports[petId]);
         
         //delete all struct elements for hydroOwnerId
        delete lostReports[petId];
        //delete key
        lostReportKeys.remove(petId);
        
        //as a good pattern, always call other contracts the last thing
        //make the transfer
        snowflake.transferSnowflakeBalanceFrom(ownerId,  claimerHydroId, reward.mul(10**18));
        return true;
    }


}
