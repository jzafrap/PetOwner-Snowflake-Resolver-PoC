pragma solidity ^0.4.24;
pragma experimental ABIEncoderV2;

import "./SnowflakeResolver.sol";


interface Snowflake {
    function whitelistResolver(address resolver) external;
    function withdrawSnowflakeBalanceFrom(string hydroIdFrom, address to, uint amount) external;
    function getHydroId(address _address) external returns (string hydroId);
}

contract PetOwner is SnowflakeResolver {
    

    //Pet fields
    struct Pet {
        //PetChoices choice; //tipo de animal
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

    constructor (address snowflakeAddress) public {
        snowflakeName = "Pet Owner - get FriendOfPets membership";
        snowflakeDescription = "Registry your Pet to be a fully qualified Friend of Pets!";
		setSnowflakeAddress(snowflakeAddress);

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
			emit PetUpdated(hydroId,pets[hydroId]);
			
        return true;
    }

    // el mapeo "public" expone un metodo get para la mascota
    function getPet(string hydroId) public view returns (string petType, string name, string desc, string petIdentification) {
        //Pet memory mascota = pets[hydroId];
        return (pets[hydroId].petType, pets[hydroId].name, pets[hydroId].desc, pets[hydroId].petIdentification);
    }

    function setPet(string petType, string name, string desc, string petIdentification) public returns (bool success)  {

        Snowflake snowflake = Snowflake(snowflakeAddress);
        string memory hydroId = snowflake.getHydroId(msg.sender);

		//1. verify all required fields
		//2. verify   petIdentification not repeated
		if(bytes(pets[hydroId].petIdentification).length == 0 && bytes(petIdentification).length != 0){
			//3. update the data
			pets[hydroId].petIdentification = petIdentification;
			pets[hydroId].petType = petType;
			pets[hydroId].name=name;
			pets[hydroId].desc=desc;
			//pets[hydroId].timestamp = now;
			emit PetUpdated(hydroId,pets[hydroId]);
			return (true);
		}else{
			return (false);
		}
    }

    event PetUpdated(string hydroId, Pet thePet);
}
