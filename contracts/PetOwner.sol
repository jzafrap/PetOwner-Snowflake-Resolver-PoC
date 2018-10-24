pragma solidity ^0.4.24;
pragma experimental ABIEncoderV2;

import "./SnowflakeResolver.sol";
import "./stringSet.sol";


interface Snowflake {
    function whitelistResolver(address resolver) external;
    function withdrawSnowflakeBalanceFrom(string hydroIdFrom, address to, uint amount) external;
    function getHydroId(address _address) external returns (string hydroId);
    function transferSnowflakeBalanceFrom(string hydroIdFrom, string hydroIdTo, uint amount) external;
    function snowflakeBalance(string hydroId) external view returns (uint);
}

contract PetOwner is SnowflakeResolver {
    
    using stringSet for stringSet._stringSet;
    

    //Pet fields
    struct Pet {
        //PetChoices choice; //tipo de animal
        
        string contactName;
        //string contactMobilePhone; unsecure!!
        string contactData; //only public data like email,twitter,telegram,facebook...
        string petType;
        string name;
        string desc;
        string petIdentification;
        //uint8 ageInYears;
        uint timestamp; //puede crease con valor now, fecha de registro
    }

    //para contener la mascota de cada hydroID
    mapping (string => Pet)  pets; //
	
    uint signUpFee = 1000000000000000000;

    enum Status {None, Pending, Found, Removed, Rewarded}
    
     
    struct LostReport{
        //string ownerHydroId;
        //string petIdentification;
        uint reportStartDate;
        string sceneDesc;
        Status status;
        uint reward;
        //string notesOnClaim;
        //string notesOnClose;
        string claimedHydroId;
        uint reportClaimDate;
        uint reportClosedDate;
    }
    
     mapping (string => LostReport[])  registryLostReports; //
     mapping (string => LostReport)  lostReports; //
     stringSet._stringSet internal lostReportsKeys;
     
    //Returning key array is possible to query by key element
    function getAllLostReportKeys() public view returns(string[]){
        return lostReportsKeys.members;
    }
    
    function getLostReport(string key)  public view returns(
        uint startDate,
        string sceneDesc,
        Status status,
        uint reward,
        //string notesOnClaim,
        //string notesOnClose,
        string claimedHydroId,
        uint reportClaimDate,
        uint reportClosedDate
        
        ){
        return (
            lostReports[key].reportStartDate,
            lostReports[key].sceneDesc,
            lostReports[key].status,
            lostReports[key].reward,
            //lostReports[key].notesOnClaim,
            //lostReports[key].notesOnClose,
            lostReports[key].claimedHydroId,
            lostReports[key].reportClaimDate,
            lostReports[key].reportClosedDate
        );
    }
    
    function getCountRegsLostReport(string key) public view returns(uint){
        return registryLostReports[key].length;
    }
    
     function getFirstRegLostReport(string key) public view returns(LostReport){
        return registryLostReports[key][0];
    }
     
    //new LostReport
    function putLostReport(string hydroId, string sceneDesc, uint reward ) public returns (bool){
        //1. report dont exists
        require(bytes(lostReports[hydroId].sceneDesc).length==0,"Lost Report already exists.");
        //2. create new struct, assign to storate mapping
        //LostReport storage newReport;
        //newReport.reportStartDate = now;
        //newReport.sceneDesc = sceneDesc;
        //newReport.reward = reward;
        //newReport.status = Status.Pending;
        //persist on storage
        lostReports[hydroId].reportStartDate = now;
        lostReports[hydroId].sceneDesc = sceneDesc;
        lostReports[hydroId].reward = reward;
        lostReports[hydroId].status = Status.Pending;
         
        lostReportsKeys.insert(hydroId);
        emit LostReportChanged(lostReports[hydroId]);
        return true;
    }
 
    function removeLostReportByOwner(string hydroId /*, string notesOnClose*/) public returns (bool){
        require(bytes(lostReports[hydroId].sceneDesc).length > 0,"Active LostReport doesn't exists");
        lostReports[hydroId].status = Status.Removed;
        lostReports[hydroId].claimedHydroId = hydroId;
        lostReports[hydroId].reportClosedDate = now;
        //lostReports[hydroId].notesOnClose = notesOnClose;
        //pass LostReport to historic
        toHistoric(hydroId);
        //delete all struct elements for hydroId
        delete lostReports[hydroId];
        //delete key
        lostReportsKeys.remove(hydroId);
        
        emit LostReportChanged(lostReports[hydroId]);
        return true;
    }
    
    function claimLostReport(string hydroId, string claimerHydroId /*,string notesOnClaim*/) public returns (bool){
       //require(hydroId != claimerHydroId, "Claimer can't be the pet owner, use removeLostReportByOwner instead.");
        require(bytes(lostReports[hydroId].sceneDesc).length > 0,"Lost Report doesn't exist");
        require(lostReports[hydroId].status == Status.Pending, "Lost Report is not pending");
       
        //change status and snowflakeDescription
        lostReports[hydroId].claimedHydroId =claimerHydroId;
        lostReports[hydroId].status =Status.Found;
        lostReports[hydroId].reportClaimDate = now;
        //lostReports[hydroId].notesOnClaim = notesOnClaim;
        emit LostReportChanged(lostReports[hydroId]);
        return true;
    }
    
    function confirmReward(string hydroOwnerId/*, string notesOnClose*/) public returns (bool){
        require(bytes(lostReports[hydroOwnerId].sceneDesc).length > 0,"LosReport doesn't exists");
        require(lostReports[hydroOwnerId].status == Status.Found, "The state of Lost Report is not found!");
        
        Snowflake snowflake = Snowflake(snowflakeAddress);
        require(snowflake.snowflakeBalance(hydroOwnerId) >= lostReports[hydroOwnerId].reward);
        
        string memory claimedHydroId = lostReports[hydroOwnerId].claimedHydroId;
        uint  reward = lostReports[hydroOwnerId].reward;
        //change state to Closed
        lostReports[hydroOwnerId].status = Status.Rewarded;
        lostReports[hydroOwnerId].reportClosedDate = now;
        //lostReports[hydroOwnerId].notesOnClose = notesOnClose;
        //pass LostReport to historic
        toHistoric(hydroOwnerId);
        //delete all struct elements for hydroOwnerId
        delete lostReports[hydroOwnerId];
        //delete key
        lostReportsKeys.remove(hydroOwnerId);
        emit LostReportChanged(lostReports[hydroOwnerId]);
        
        //as a good pattern, always call other contracts the last thing
        //make the transfer
        snowflake.transferSnowflakeBalanceFrom(hydroOwnerId,  claimedHydroId, reward);
        return true;
    }
    
    //move from active to registry
    function toHistoric(string hydroId) internal{
        //get from lostReports
        LostReport storage reg = lostReports[hydroId];
        //put in RegistryLostReports
        registryLostReports[hydroId].push(reg);
        emit RegLogUpdated(hydroId, registryLostReports[hydroId].length);
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
        
		//3. update the data
			pets[hydroId].petIdentification = "petId";
			pets[hydroId].petType = "type of pet";
			pets[hydroId].name="my pet name";
			pets[hydroId].desc="pet description";
			//pets[hydroId].timestamp = now;
			pets[hydroId].contactName = "owner's name";
			//pets[hydroId].contactMobilePhone = "owner's phone";
			pets[hydroId].contactData = "owner's public contact data";
			emit PetUpdated(hydroId);
			
        return true;
    }
    
   
    
     //get pet data from hydroId
    function getPet(string hydroId) public view returns (string petType, string name, string desc, string petIdentification,
        string contactName, string contactData) {
       return (pets[hydroId].petType, pets[hydroId].name, pets[hydroId].desc, pets[hydroId].petIdentification,
       	pets[hydroId].contactName,	pets[hydroId].contactData );
    }

    //set Pet data for hydroId
    function setPet(string hydroId, string petType, string name, string desc, string petIdentification,
    string contactName, string contactData) public returns (bool success)  {
      	//1. verify all required fields
		//2. verify   petIdentification not repeated
		//if(bytes(pets[hydroId].petIdentification).length == 0 && bytes(petIdentification).length != 0){
			//3. update the data
			pets[hydroId].petIdentification = petIdentification;
			pets[hydroId].petType = petType;
			pets[hydroId].name=name;
			pets[hydroId].desc=desc;
			//pets[hydroId].timestamp = now;
			pets[hydroId].contactName = contactName;
			//pets[hydroId].contactMobilePhone = contactMobilephone;
			pets[hydroId].contactData = contactData;
			emit PetUpdated(hydroId);
			return (true);
		//}else{
		//	return (false);
		//}
    }

    event PetUpdated(string hydroId);
    event RegLogUpdated(string hydroId, uint length);
    event LostReportChanged(LostReport lostReport);
}
