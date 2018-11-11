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
    
    using stringSet for stringSet._stringSet;
     using SafeMath for uint;
    
    //OwnerFields
    struct Owner{
        string snowflakeId; //PK
        string contactName;
        string contactData;
        string[] petIds;
    }

   //owners registry by snowflakeId
    mapping (string => Owner) owners;
    
    //Pet fields
    struct Pet {
        string petIdentification; //PK
        string petType;
        string breed;
        string name;
        string desc;
        string imgUrl;
    }
    
     
    //pets registry by petIdentification(PK)
    mapping (string => Pet)  pets; //
    
    struct LostReport{
        string petIdentification; //PK
        Status status;
        string sceneDesc;
        string location;
        uint reward;
        string claimerHydroId;
    }

 
    uint signUpFee = uint(1).mul(10**18);

    enum Status {None, Pending, Found, Removed, Rewarded}
    
    //lost report of a petIdentification
    mapping (string => LostReport) private lostReports; 
    
    //all active lost report keys
    stringSet._stringSet internal lostReportsKeys;
     
     //Events
     
    //when pet data changes
    event PetUpdated(
        string hydroId,
        uint date,
        Pet pet
    );
    
    
    //when lost report changes: reports, modifies, claimed, closed...
    //to be used to list an historic of pet incidences
    event LostReportChanged(
        string petIdentification, 
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
     
     
    constructor () public {
        snowflakeAddress = 0x8b8B004aBF1eE64e23D6088B73873898d8408A6d; //rinkeby address of snowflake contract
		snowflakeName = "Pet Owner - get FriendOfPets membership";
        snowflakeDescription = "Registry your Pet to be a fully qualified Friend of Pets!";
		//setSnowflakeAddress(snowflakeAddress);

        callOnSignUp = true;
		Snowflake snowflake = Snowflake(snowflakeAddress);
        snowflake.whitelistResolver(address(this));
        
    }

    // implement signup function
    function onSignUp(string hydroId, uint allowance) public senderIsSnowflake()  returns (bool) {
        require(allowance >= signUpFee, "Must set an allowance of at least 1 HYDRO.");
        Snowflake snowflake = Snowflake(snowflakeAddress);
        snowflake.withdrawSnowflakeBalanceFrom(hydroId, owner, signUpFee);
        
		//3. update the mapping owners
		owners[hydroId].contactName = "Please update with owner's name";
		owners[hydroId].contactData = "Please update with owner's public contact info";

        return true;
    }
    
    function getOwnerPets(string ownerId) public view returns(string[]){
        return owners[ownerId].petIds;    
    }
    
      
     //get pet data from petIdentification
    function getPet(string petIdentification) public view returns (string petType, string breed, string name, string desc, string imgUrl) 
    {
       return( 
            pets[petIdentification].petType, 
            pets[petIdentification].breed, 
            pets[petIdentification].name, 
            pets[petIdentification].desc, 
            pets[petIdentification].imgUrl
       	);
    }

    //The owner creates a new pet
    function addPet(string ownerId, string petIdentification, string petType,  string breed, string name, string desc, string imgUrl) public _onlyOwner(ownerId) returns (bool success)  
    {
        //0. sender must be ownerId
      	//1. verify all required fields
		//2. verify   petIdentification not repeated
		 require(bytes(pets[petIdentification].desc).length == 0,"A pet already registered with this petIdentification");
		
		//3. update the data
		
		pets[petIdentification].petIdentification =petIdentification;
		pets[petIdentification].petType = petType;
		pets[petIdentification].breed=breed;
		pets[petIdentification].name=name;
		pets[petIdentification].desc=desc;
		pets[petIdentification].imgUrl=imgUrl;
		
		//4. register pet ownership
		owners[ownerId].petIds.push(petIdentification);
		
		emit PetUpdated(petIdentification,now,pets[petIdentification]);
		return (true);
    }
    
     function updatePet(string ownerId, string petIdentification, string petType,  string breed, string name, string desc, string imgUrl) public _onlyOwner(ownerId) returns (bool success)  
    {
        //0. sender must be ownerId
      	//1. verify all required fields
		//2. verify   petIdentification already exists
			 require(bytes(pets[petIdentification].desc).length >0,"No pet exists with that petId");
		//3. update the data
			//pets[hydroId].petIdentification = petIdentification;
			pets[petIdentification].petType = petType;
			pets[petIdentification].breed=breed;
			pets[petIdentification].name=name;
			pets[petIdentification].desc=desc;
			pets[petIdentification].imgUrl=imgUrl;
		
		
			emit PetUpdated(petIdentification,now,pets[petIdentification]);
			return (true);
		//}else{
		//	return (false);
		//}
    }


    //Returning key array is possible to query by key element
    function getAllLostReportKeys() public view returns(string[]){
        return lostReportsKeys.members;
    }
    
    function getLostReport(string petIdentificacion)  public view returns(
        Status status,
        string sceneDesc,
        string location,
        uint reward,
        string claimerHydroId
        ){
        return (
            lostReports[petIdentificacion].status,
            lostReports[petIdentificacion].sceneDesc,
            lostReports[petIdentificacion].location,
            lostReports[petIdentificacion].reward,
            lostReports[petIdentificacion].claimerHydroId
        );
    }

    //new LostReport
    function putLostReport(string ownerId, string petIdentification, string sceneDesc, string location, uint reward ) public _onlyOwner(ownerId) returns (bool){
        //1. report dont exists
        require(bytes(lostReports[petIdentification].sceneDesc).length==0,"Lost Report already exists.");
        //2. create new struct, assign to storate mapping
        //persist on storage
        lostReports[petIdentification].sceneDesc = sceneDesc;
        lostReports[petIdentification].location = location;
        lostReports[petIdentification].reward = reward;
        lostReports[petIdentification].status = Status.Pending;

        lostReportsKeys.insert(petIdentification); //can exists?
        emit LostReportChanged(petIdentification,now, lostReports[petIdentification]);
        return true;
    }
    
    
    //new LostReport
    function updateLostReport(string ownerId, string petIdentification, string sceneDesc, string location, uint reward ) public _onlyOwner(ownerId) returns (bool){
        //1. report dont exists
        require(bytes(lostReports[petIdentification].sceneDesc).length>0,"Lost Report don't exists.");
        //2. create new struct, assign to storate mapping
        //persist on storage
        lostReports[petIdentification].sceneDesc = sceneDesc;
        lostReports[petIdentification].location = location;
        lostReports[petIdentification].reward = reward;
        lostReports[petIdentification].status = Status.Pending;
         
        lostReportsKeys.insert(petIdentification); //can exists?
        emit LostReportChanged(petIdentification,now, lostReports[petIdentification]);
        return true;
    }
 
    function removeLostReport(string ownerId, string petIdentification) public _onlyOwner(ownerId) returns (bool){
       
         
        //petIdentification must have a report
        require(bytes(lostReports[petIdentification].sceneDesc).length > 0,"Active LostReport doesn't exists");
        lostReports[petIdentification].status = Status.Removed;
       
       
         emit LostReportChanged(petIdentification, now,lostReports[petIdentification]);
        //delete all struct elements for hydroId
        delete lostReports[petIdentification];
        //delete key
        lostReportsKeys.remove(petIdentification);
        
       
        return true;
    }
    
    function claimLostReport(string petIdentification, string claimerHydroId /*,string notesOnClaim*/) public returns (bool){
       //require(hydroId != claimerHydroId, "Claimer can't be the pet owner, use removeLostReportByOwner instead.");
        require(bytes(lostReports[petIdentification].sceneDesc).length > 0,"Lost Report doesn't exist");
        require(lostReports[petIdentification].status == Status.Pending, "Lost Report is not pending");
       
        //change status and snowflakeDescription
        lostReports[petIdentification].claimerHydroId =claimerHydroId;
        lostReports[petIdentification].status =Status.Found;
       
        //lostReports[hydroId].notesOnClaim = notesOnClaim;
        emit LostReportChanged(petIdentification,now,lostReports[petIdentification]);
        return true;
    }
    
    function confirmReward(string ownerId, string petIdentification) public _onlyOwner(ownerId) returns (bool){
        //sender must be pet owner
        
        //report must exists
        require(bytes(lostReports[petIdentification].sceneDesc).length > 0,"LosReport doesn't exists");
        //report status must be found
        require(lostReports[petIdentification].status == Status.Found, "The state of Lost Report is not found!");
        
        Snowflake snowflake = Snowflake(snowflakeAddress);
        require(snowflake.snowflakeBalance(ownerId) >= lostReports[petIdentification].reward.mul(10**18));
        
        string memory claimerHydroId = lostReports[petIdentification].claimerHydroId;
        uint  reward = lostReports[petIdentification].reward;
        //change state to Closed
        lostReports[petIdentification].status = Status.Rewarded;
       
       
        //LostReportChanged event
        emit LostReportChanged(petIdentification, now,lostReports[petIdentification]);
         
         //delete all struct elements for hydroOwnerId
        delete lostReports[petIdentification];
        //delete key
        lostReportsKeys.remove(petIdentification);
        
        //as a good pattern, always call other contracts the last thing
        //make the transfer
        snowflake.transferSnowflakeBalanceFrom(ownerId,  claimerHydroId, reward.mul(10**18));
        return true;
    }
    

    


  
    
}
