"# PetOwner-Snowflake-Resolver-PoC" 

This is a PoC of a Snowflake Resolver Contract.
Abstract:

- Snowflake is an identity management system that allows grouping one or more wallet addresses under an unique Id called HydroId; this ID is easy to remember, and acts like a grouping wallet, where you can move funds from/to the linked addresses.

- By implementing DApps called "Resolvers", it is possible to interact from the snowflake, making payments or implementing any logic that smart contracts supports.

This example is an implementation of a Resolver covering this use cases:

1. There is a registry of pet owners in the blockchain.
2. This registry can be used to find pet owners in case of pet lost, when the pet is recovered and identified by thirds.
3. This registry can potentially be used to give insurance services, pet walking services, helping in lost of the pets, etc.
4. Registering a pet in this registry costs a fee of X hydros (here is the payment scenario).
5. You only pay once when registering a new pet. The pet ID must be unique (it's assumed is a PK field). 
6. After registration, you only can change description data without a fee. The pet owner pays the transaction fees.
7. An Hydro ID can own 1..N pets; it is posible to register more than one pet, each of them must pay the registration fee.
8. In any moment, the hydroId owner can de-register a pet (in case of death, for example). Initial fee isn't returned. The pet owner pays the transaction fees.
9. This registry of pets can be used to reporting lost+found pets, making all the info avalaible to pet owners. 
10. Pet owner can make a report of lost pet (date, description of scene)
11. Pet owner can make a report of found pet (date, description of scene, petId)
12. Pet owners can access a list of incidences about the pets of their own. For example, Have anybody found my lost pet?!?
9. From the snowflake dashboard, the interface must have this functions:
Use Case 1: List my registered pets
Use Case 2: Register a new Pet of my own (paying the fee)
Use Case 3: Modify allowed fields of the pet (description), persisting the changes on blockchain.
Use Case 4: Delete a pet of my own.
Use Case 5: Report the lost of a pet
Use Case 6: See reports of my interest:
  - reported by me
  - reported to any of my pets (petId coincidence)

From this, we can make much more functionality, but this is only a PoC, and thats ok!.

Can include a use case:
- pet owner put a reward (in hydro) in case of found lost pet.
- somebody founds the pet and claims the reward.
- after the resolution, pet owner pays the reward, and close incidence.

