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
    //v.0.7: implementation on "use-case level" verifications
    //v.0.8:
    //   - bug correction, deleted escrow mapping.
    //   - added _canModifyReward modifier
    //   - added getMaxAllowedReward public function
    //   - added FundsChanged event and emitFundsChanged function
    
    
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
        uint claimerEin;
    }

    //one hydro is represented as 1000000000000000000
    uint private signUpFee = uint(1).mul(10**18);

    enum Status {None, Pending, Found, Removed, Rewarded}
    
    //enum FundMovement {Deposit, Withdraw}
    
     //pets registry by petId(PK)
    mapping (string => Pet)  private pets; //
    
    //owners registry by ein
    mapping (uint => Owner) private owners;
    
    //lost report Struct of a petId
    mapping (string => LostReport) private lostReports; 
    
    //all active lost report keys; used to list in frontend
    stringSet._stringSet private  lostReportKeys;
    
     //Events
  
    //event FundsChanged(
    //    uint indexed ein,
    //    string petId,
    //    uint date,
    //    Status status,
    //    uint funds,
    //    FundMovement movement
    //);
    
    // function emitFundsChanged( uint ownerId, string memory petId, Status status, FundMovement movement)
    //private{
    //   SnowflakeInterface snowflake = SnowflakeInterface(snowflakeAddress);
    //    uint funds = snowflake.resolverAllowances(ownerId,address(this));
    //    emit FundsChanged(ownerId, petId, now, status,funds, movement);
    //} 
    
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
    
    function emitEventNewPet(string memory petId) 
    private{
        bytes32 hashedPetId = keccak256(abi.encode(petId));
        emit LostReportChanged(hashedPetId,petId, now,Status.None,"",0,0);
    }
    
    function  emitEventV2 (  string memory petId, LostReport memory lostReport) 
    private{
        bytes32 hashedPetId = keccak256(abi.encode(petId));
        emit LostReportChanged(hashedPetId,petId, now,lostReport.status,lostReport.sceneDesc,lostReport.reward,lostReport.claimerEin);
    }
      
        //modifiers
     //verify if transaction sender is the owner himself
     modifier _onlyOwner(uint ownerId)
     {   
         SnowflakeInterface snowflake = SnowflakeInterface(snowflakeAddress);
         IdentityRegistryInterface identityRegistry = IdentityRegistryInterface(snowflake.identityRegistryAddress());
         require(ownerId == identityRegistry.getEIN(msg.sender));
         _;
     }
     
      //modifiers
     //verify if transaction sender is the pet owner
     modifier _onlyPetOwner(string memory petId)
     {   
         SnowflakeInterface snowflake = SnowflakeInterface(snowflakeAddress);
         IdentityRegistryInterface identityRegistry = IdentityRegistryInterface(snowflake.identityRegistryAddress());
         require(pets[petId].ownerId == identityRegistry.getEIN(msg.sender));
         _;
     }
     
     //verify if transaction sender is not the pet owner
     modifier _onlyNotPetOwner(string memory petId)
     {   
         SnowflakeInterface snowflake = SnowflakeInterface(snowflakeAddress);
         IdentityRegistryInterface identityRegistry = IdentityRegistryInterface(snowflake.identityRegistryAddress());
         require(pets[petId].ownerId != identityRegistry.getEIN(msg.sender));
         _;
     }
     
     modifier _reportNotActive(string memory petId)
     {
        //require(bytes(pets[petId].desc).length >0,"No pet exists with that petId");
        require(!lostReportKeys.contains(petId));
        _;
     }
    
    modifier _petExists(string memory petId)
     {
        require(bytes(pets[petId].petId).length >0,"No pet exists with that petId");
        _;
     }
     
    modifier _uniquePetId(string memory petId){
        //require(pets[petId].length==0);
         require(bytes(pets[petId].petId).length ==0,"No pet exists with that petId");
        _;
    } 
    
    //only can reward if:
    //snowflake funds >= reward
    //and  reward <= snowflake resolver allowance
    modifier _canReward(uint ownerId,uint reward){
        require(reward >=0);
        if(reward > 0){
            SnowflakeInterface snowflake = SnowflakeInterface(snowflakeAddress);
            require(snowflake.resolverAllowances(ownerId,address(this)) >= reward);
            require(snowflake.deposits(ownerId) >= reward);
        }
        _;   
    }
    
    //if new reward is greater, 
    //snowflake funds >= reward increment
    //and  reward increment <= snowflake resolver allowance
    modifier _canModifyReward(uint ownerId,string memory petId, uint newreward){
        if(lostReports[petId].reward < newreward){
            //new reward is greater than last
            uint diff = newreward - lostReports[petId].reward;
            SnowflakeInterface snowflake = SnowflakeInterface(snowflakeAddress);
            require(snowflake.resolverAllowances(ownerId,address(this)) >= diff);
            require(snowflake.deposits(ownerId) >= diff);
        }
       _;
    }
    
    //debug method to get max reward
    
    modifier _reportStatusMustBe(string memory petId, Status status){
        require(lostReports[petId].status == status,"Unexpected report status");
        _;
    }
    
     modifier _canUnclaim(string memory petId)
     {   
        SnowflakeInterface snowflake = SnowflakeInterface(snowflakeAddress);
        IdentityRegistryInterface identityRegistry = IdentityRegistryInterface(snowflake.identityRegistryAddress());
        uint ownerId = pets[petId].ownerId;
        uint claimerHydroId = lostReports[petId].claimerEin;
        require(
            (identityRegistry.getEIN(msg.sender) == ownerId)
            ||
           (identityRegistry.getEIN(msg.sender) == claimerHydroId)
        );
         _;
     }
     
    constructor (address snowflakeAddress)
        SnowflakeResolver("Pet Owner Resolver v0.8 - get your Pet Friend membership", "Become a member of Pet Friends community and register your pets!", snowflakeAddress, true, false) public
    {  }
    
       // implement signup function
    function onAddition(uint ein, uint, bytes memory extraData) 
    public 
    senderIsSnowflake() 
    returns (bool) {
        SnowflakeInterface snowflake = SnowflakeInterface(snowflakeAddress);
        snowflake.withdrawSnowflakeBalanceFrom(ein, owner(), signUpFee);

      	//3. update the mapping owners
      	 (string memory contactName, string memory contactData) = abi.decode(extraData, (string, string));
		owners[ein].contactName = contactName;
		owners[ein].contactData = contactData;

       // emit StatusSignUp(ein);
        return true;
    }
     
    function onRemoval(uint, bytes memory) 
    public 
    senderIsSnowflake() returns (bool) {
        //delete all pets
       // for(uint i=0;i<owners[ein].petIds.length;i++){
        //    string memory petId = owners[ein].petIds[i];
        //    Pet apet = pets[petId];
        //    if(lostReportKeys.contains(petId)){
        //        //remove report
        //        //if Pending, Found or Claimed:
        //        
        //    }
        //}
        //delete all reports
        //return all escrow if any
        //delete owner
         return true;
    }

     //event StatusSignUp(uint ein);
    
    //function getMaxAllowedReward(uint ownerId)
    //public 
    //returns (uint maxAllowedReward){
    //      SnowflakeInterface snowflake = SnowflakeInterface(snowflakeAddress);
    //      uint allowance = snowflake.resolverAllowances(ownerId,address(this));
    //      uint deposits = snowflake.deposits(ownerId);
    //      if(allowance > deposits) 
    //        return (deposits);
    //      else{
    //          return (allowance);
    //      }
    //}
    
    function getOwner(uint ownerId)
    public view 
    returns (string memory contactName, string memory contactData ){
        return( owners[ownerId].contactName,
                owners[ownerId].contactData)  ;  
    }
    
    function getPetOwner(string memory petId)  
    public view 
    returns (uint ownerId,string memory contactName, string memory contactData ){
        return(
            pets[petId].ownerId,
            owners[pets[petId].ownerId].contactName,
            owners[pets[petId].ownerId].contactData
        );
        
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
    
    function getOwnerPets(uint ownerId) 
    public view 
    returns(string[] memory){
         return owners[ownerId].petIds;
    }
    
      
     //get pet data from petId
    function getPet(string memory petId) 
    public view 
    returns (string memory petType, string memory name, string memory desc, string memory imgUrl) 
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
		
		emitEventV2(petId, lostReports[petId]);

		return (true);
    }
    
    function updatePet(uint ownerId, string memory petId, string memory petType,  string memory name, string memory desc, string memory imgUrl) 
    public 
    _onlyPetOwner(petId)
    _petExists(petId)
    returns (bool success)  
    {
        //0. sender must be ownerId
      	//1. verify all required fields
		//2. verify   petId already exists
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
    function getAllLostReportKeys() 
    public view 
    returns(string[] memory){
        return lostReportKeys.members;
    }
    
    function getLostReport(string memory petId)  
    public view 
    returns(
        Status status,
        string memory sceneDesc,
        uint reward,
        uint claimerHydroId
        ){
        return (
            lostReports[petId].status,
            lostReports[petId].sceneDesc,
            lostReports[petId].reward,
            lostReports[petId].claimerEin
        );
    }
    
    

    //new LostReport
    function putLostReport(uint ownerId, string memory petId, string memory sceneDesc, uint reward ) 
    public 
    _onlyPetOwner(petId)
    //_petExists(petId)
    _canReward(ownerId,reward)
    _reportNotActive(petId)
    returns (bool){
        //1. report dont exists
       require(bytes(lostReports[petId].sceneDesc).length==0,"Lost Report already exists.");
        //2. create new struct, assign to storate mapping
        //persist on storage
        lostReports[petId].sceneDesc = sceneDesc;
        lostReports[petId].reward = reward;
        lostReports[petId].status = Status.Pending;

        lostReportKeys.insert(petId); //can exists?
        
        //escrow reward from snowflake to resolver
        SnowflakeInterface snowflake = SnowflakeInterface(snowflakeAddress);
        snowflake.withdrawSnowflakeBalanceFrom(ownerId, address(this), reward.mul(10**18));
        //emitFundsChanged(ownerId, petId, Status.Pending, FundMovement.Withdraw);
        emitEventV2(petId, lostReports[petId]);
        return true;
    }
    
    
    //new LostReport
    function updateLostReport(uint ownerId, string memory petId, string memory sceneDesc, uint reward ) 
    public 
    _onlyPetOwner(petId) 
    _canModifyReward(ownerId,petId,reward)
    _reportStatusMustBe(petId,Status.Pending)
    returns (bool){
     
        //1. report dont exists
        //require(bytes(lostReports[petId].sceneDesc).length>0,"Lost Report don't exists.");

        //update escrow reward, transferring or withdrawing from/to resolver if needed
        updateEscrowReward(ownerId,petId,reward);
        
        //2. create new struct, assign to storate mapping
        //persist on storage
        lostReports[petId].sceneDesc = sceneDesc;
        lostReports[petId].reward = reward;
        lostReports[petId].status = Status.Pending;
        
        lostReportKeys.insert(petId); //can exists?
        emitEventV2(petId, lostReports[petId]);
        return true;
    }
    
    //Update escrow for owner
    function updateEscrowReward(uint ownerId,string memory petId, uint reward)
    private{
         //escrow reward from snowflake to resolver
         if(lostReports[petId].reward != reward){
             if(lostReports[petId].reward < reward){
                 //Handle withdraw of remaining esscrow
                 SnowflakeInterface snowflake = SnowflakeInterface(snowflakeAddress);
                 snowflake.withdrawSnowflakeBalanceFrom(ownerId, address(this), (reward - lostReports[petId].reward).mul(10**18));
                 //emitFundsChanged(ownerId, petId, Status.Pending, FundMovement.Withdraw);
             }else{
                 //Handle transfer of necessary escrow
                transferHydroBalanceTo(ownerId,(lostReports[petId].reward - reward).mul(10**18));
                //emitFundsChanged(ownerId, petId, Status.Pending, FundMovement.Deposit);
             }
         }
    }
 
    //owner can remove a lost report, when he finds the pen again, for example, o is found dead, etc.
    function removeLostReport(uint ownerId, string memory petId) 
    public 
    _onlyPetOwner(petId)
    _reportStatusMustBe(petId,Status.Pending)
    returns (bool){
        //petId must have a report
        //require(bytes(lostReports[petId].sceneDesc).length > 0,"Active LostReport doesn't exists");
        lostReports[petId].status = Status.Removed;
       
        //return escrow
        if(lostReports[petId].reward > 0){
             //return reward to owner
             transferHydroBalanceTo(ownerId,lostReports[petId].reward.mul(10**18));
             //emitFundsChanged(ownerId, petId, Status.Removed, FundMovement.Deposit);
        }
       
        emitEventV2(petId, lostReports[petId]);
        
        //delete all struct elements for hydroId
        delete lostReports[petId];
        //delete key
        lostReportKeys.remove(petId);
        return true;
    }
    
    //somebody claims the pet found
    function claimLostReport(string memory petId, uint claimerHydroId /*,string notesOnClaim*/) 
    public
    _onlyNotPetOwner(petId)
    _reportStatusMustBe(petId,Status.Pending)
    returns (bool){
        require(bytes(lostReports[petId].sceneDesc).length > 0,"Lost Report doesn't exist");
        //change status and snowflakeDescription
        lostReports[petId].claimerEin =claimerHydroId;
        lostReports[petId].status =Status.Found;
        emitEventV2(petId, lostReports[petId]);
        return true;
    }
    
    
    //unclaim previos claimed report: only can unclaim the owner or the claimer or pet owner   
    function unclaimLostReport(string memory petId) 
    public 
    _canUnclaim (petId) 
    _reportStatusMustBe(petId,Status.Found)
    returns (bool){
        require(bytes(lostReports[petId].sceneDesc).length > 0,"Lost Report doesn't exist");

        //change status and snowflakeDescription
        lostReports[petId].claimerEin =0;
        lostReports[petId].status =Status.Pending;
       
        emitEventV2(petId, lostReports[petId]);
        return true;
    }
    
    function confirmReward(uint ownerId, string memory petId) 
    public 
    _onlyPetOwner(petId)
    _reportStatusMustBe(petId,Status.Found)
    returns (bool){
        //report must exists
        //require(bytes(lostReports[petId].sceneDesc).length > 0,"LosReport doesn't exists");

        //change state to Closed
        lostReports[petId].status = Status.Rewarded;
       
        //as a good pattern, always call other contracts the last thing
        //make the transfer
        //snowflake.transferSnowflakeBalanceFrom(ownerId,  claimerHydroId, reward.mul(10**18));
        transferHydroBalanceTo(lostReports[petId].claimerEin,lostReports[petId].reward.mul(10**18));
        //emitFundsChanged(lostReports[petId].claimerEin, petId, Status.Rewarded, FundMovement.Deposit);
        //LostReportChanged event
        emitEventV2(petId, lostReports[petId]);
        
        //delete all struct elements for hydroOwnerId
        delete lostReports[petId];
        //delete key
        lostReportKeys.remove(petId);
    
        return true;
    }

   

}
