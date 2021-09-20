MARKETPLACE

# TODO  15.06.2021
// TODO: pay bid to Seller after every bid <- claim can be done by both sides
// TODO: ERC20 (UNIQ) picked for fee-free bids
// TODO: 50% off market fee price if have certain number UNIQ on wallet/market?
// those two are too expensive
// TODO: 50% off market fee price if have certain number UNIQ on wallet/market?
// TODO: UNIQ tokens on market in certain number lowering/disabling fee for user
// TODO: NFT tokens are handling royalty in different ways <- addred try/cath

# Requirements before deployment - PO needs to collect from stakeholders
owner = msg.sender;
maxTime = maxOfferTime;
prolongOffer = offerProlong;

# TEST SCENARIOS
1. As a user, I want to sell item which I am owner
    1. Check all requires cases
    2. Check all if/else cases
2. As a user, I want to bid item 
    1.  Check all if/else cases
3. As an item owner, I want to claim item which has not had any bids
    1. Check all if/else cases
4. As a user who won, I want to claim item 
    1. Check all if/else cases
5. As an item owner, I want to resell item which has not had any bids
    1. Check all if/else cases
    2. Check all requires cases
6. As a user who won, I want to resell item 
    1. Check all if/else cases
    2. Check all requires cases
7. As a dApp, I want to get a total offer number
8. As a dApp, I want to get an offer by index
9. As a dApp, I want to get minimum/last? bid on offer
10. As a backend app, I want to get current number of offers
11. As a dApp, I want to get an offer by address and tokenId
12. As a dApp, I want to get all offers from the market - CAN BE LIMITED IF TOO MANY OFFERS
    1. Check all if/else cases
13. As a dApp, I want to get all offers from the market using pagination - getOffersByRange
    1. Check all if/else cases
14. As a dApp, I want to get all offers by a particular user
    1. Check all if/else cases
15. As a dApp, I want to get all number of all offers by a particular user - CAN BE LIMITED IF TOO MANY OFFERS
16. As a dApp, I want to get list of all offers by a particular user using pagination
    1. Check all if/else cases
17. As a dApp, I want to get list of all bids for a particular user  - CAN BE LIMITED IF TOO MANY BIDS
    1. Check all if/else cases
18. As a dApp, I want to get a total number of all bids for a particular user - getBidsCount
19. As a dApp, I want to get list of all bids for a particular user using pagination 
    1. Check all if/else cases
    2. Check all requires cases
20. As an admin, I want to add a new token to the market
21. As an admin, I want to remove a token from the market (what is happening with offers based on this contract) ??
22. As an admin, I want to add a new payment token
23. As an admin, I want to remove a payment token (what is happening with offers based on this payment token) ??
24. getFeeCollected - MORE EXPLANATION NEEDED
25. As an admin, I want to withdraw all funds

Test all private methods - should be covered with all requires in public methods
