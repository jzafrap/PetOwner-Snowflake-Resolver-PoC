var PetOwner = artifacts.require("./PetOwner.sol");

module.exports = function(deployer) {
  deployer.deploy(PetOwner);
};
