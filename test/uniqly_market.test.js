const UniqlyMarket = artifacts.require("UniqlyMarket");
const simpleNFT = artifacts.require("simpleNft");
const simpleErc20 = artifacts.require("simpleErc20");

const {
  BN,           // Big Number support
  time,
  constants,    // Common constants, like the zero address and largest integers
  expectEvent,  // Assertions for emitted events
  expectRevert, // Assertions for transactions that should fail
} = require('@openzeppelin/test-helpers');
const { assertion } = require('@openzeppelin/test-helpers/src/expectRevert');
const { ZERO_ADDRESS } = constants;

let gasUsage = [];
function logGas(ret, fname) {
  let gas = ret.receipt.gasUsed;
  gasUsage.push({ name: fname, value: gas });
}

contract("UniqlyMarket", function (accounts) {

  const [owner, publisher, user1, user2, user3, user4] = accounts;

  let market;
  let payToken1;
  let payToken2;
  let nftToken1;
  let nftToken2;
  let startTime = Number();
  let day = Number(time.duration.days(1));
  let days2 = day * 2;
  let second = Number(time.duration.seconds(1));
  let week = Number(time.duration.days(7));
  let weeks2 = week * 2;
  let weeks4 = week * 4;
  let month = 30 * day;
  let months2 = 2 * month;

  before(async function () {
    // deploy contracts
    //constructor(uint256 maxOfferTime, uint256 offerProlong)
    market = await UniqlyMarket.new(weeks4, 60 * 15, { from: owner });

    payToken1 = await simpleErc20.new({ from: publisher })
    payToken2 = await simpleErc20.new({ from: publisher })
    payToken3 = await simpleErc20.new({ from: publisher })
    nftToken1 = await simpleNFT.new({ from: publisher })
    nftToken2 = await simpleNFT.new({ from: publisher })

    // mint and send tokens
    await nftToken1.mint("1", user1, "0"); // user1, 1 token, no royalties
    await nftToken1.mint("1", user2, "100"); //user2. 1 token, 1% royalties
    await nftToken2.mint("1", user1, "50"); // 1 other token, 0.5% royalties
    await nftToken2.mint("1", user2, "0"); // 1 other token, no royalties

    await nftToken2.mint("1", user3, "0"); // 1 other token, no royalties
    await nftToken2.mint("1", user2, "0"); // 1 other token, no royalties
    
    await nftToken1.mint("10", user1, "0"); // 10 other token, no royalties
    await nftToken2.mint("10", user2, "0"); // 10 other token, no royalties

    await payToken1.transfer(user3, "1000000", { from: publisher });
    await payToken1.transfer(user4, "1000000", { from: publisher });
    await payToken2.transfer(user3, "10000000", { from: publisher });
    await payToken2.transfer(user4, "10000000", { from: publisher });

    // allow payment methods
    // function addPaymentToken(address token, uint256 marketFee)
    resp = await market.addPaymentToken(payToken1.address, "5000", { from: owner }) // this have no fees
    logGas(resp, "addPaymentToken")
    resp = await market.addPaymentToken(payToken2.address, "5000", { from: owner }) // this have 0.5% fee
    logGas(resp, "addPaymentToken")
    resp = await market.addPaymentToken(ZERO_ADDRESS, "5000", { from: owner }) // ETH have 0.5% fee
    logGas(resp, "addPaymentToken")
    // allow NTF tokens
    resp = await market.addNftToken(nftToken1.address, { from: owner })
    logGas(resp, "addNftToken")
    resp = await market.addNftToken(nftToken2.address, { from: owner })
    logGas(resp, "addNftToken")

    startTime = Number(await time.latest())
  })
  it('have all contracts in place', async function () {
    expect(market.address).not.eql(ZERO_ADDRESS)
    expect(nftToken1.address).not.eql(ZERO_ADDRESS)
    expect(nftToken2.address).not.eql(ZERO_ADDRESS)
    expect(payToken1.address).not.eql(ZERO_ADDRESS)
    expect(payToken2.address).not.eql(ZERO_ADDRESS)
  })

  describe('place offers', function () {
    it('throws badly configured offers', async function () {
      let bad = [];
      bad[1] = [user1, payToken2.address, 1, 5000, 0, 0, 0] // wrong NFT token address
      bad[2] = [nftToken2.address, user2, 1, 5000, 0, 0, 0] // wrong payment token address
      bad[3] = [nftToken2.address, payToken2.address, 1, 5000, 500, 0, 0]  // max price below price
      bad[4] = [nftToken1.address, payToken1.address, 0, 500, 0, 0, week] //no step
      bad[5] = [nftToken2.address, payToken2.address, 1, 5000, 0, 10, 0]  // buy-now but step set
      bad[6] = [nftToken2.address, ZERO_ADDRESS, 0, 300, 30000, 0, (day * 10)]  // auction+buy-now but no step
      bad[7] = [nftToken2.address, ZERO_ADDRESS, 0, 300, 30000, 0, 0]  // buy-now but max price set
      bad[8] = [nftToken1.address, payToken1.address, 0, 500, 1000, 1, 1] // too short
      bad[9] = [nftToken1.address, payToken1.address, 0, 500, 0, 1, startTime + months2] // too long
      let err = [];
      err[1] = "Wrong NFT token address"
      err[2] = "Wrong payment token"
      err[3] = "MaxPrice set"
      err[4] = "MinStep not set"
      err[5] = "MinStep set"
      err[6] = "MinStep not set"
      err[7] = "MaxPrice set"
      err[8] = "Wrong timestamp set"
      err[9] = "Wrong timestamp set"
      await nftToken2.setOperator(market.address, { from: user2 })
      await nftToken1.setOperator(market.address, { from: user2 })

      for (let i = 1; i < 10; i++) {
        await expectRevert(market.sell(bad[i][0], bad[i][1], bad[i][2], bad[i][3], bad[i][4], bad[i][5], bad[i][6], { from: user2 }), err[i])
      }

    })

    it('accepts all types of sell', async function () {
      let offer = [];
      offer[1] = [nftToken1.address, payToken1.address, 0, 500, 1000, 1, startTime + week, user1] // user1 token 1/0 ; auction
      offer[2] = [nftToken1.address, payToken2.address, 1, 500, 0, 5, startTime + weeks2, user2]  // user2 token 1/1; auction
      offer[3] = [nftToken2.address, ZERO_ADDRESS, 0, 300, 30000, 10, startTime + (day * 10), user1]  // user1, token 2/0; ETH auction+buy-now
      offer[4] = [nftToken2.address, payToken2.address, 1, 5000, 0, 0, 0, user2]  // user2, token 2/1 ; buy-now
      offer[5] = [nftToken2.address, payToken2.address, 3, 2000, 0, 0, 0, user2]  // user2, token 2/1 ; buy-now
      await nftToken2.setOperator(market.address, { from: user1 })
      await nftToken1.setOperator(market.address, { from: user1 })
      for (let i = 1; i < 6; i++) {
        ret = await market.sell(offer[i][0], offer[i][1], offer[i][2], offer[i][3], offer[i][4], offer[i][5], offer[i][6], { from: offer[i][7] })
        logGas(ret, "market.sell " + i)
      }
    })

    it('throws when try sell again', async function () {
      await expectRevert(market.sell(nftToken1.address, payToken1.address, 0, 500, 0, 1, startTime + week, { from: user1 }), "Token already on market")
    })
  })

  describe('bid offers', function () {
    it('throws badly configured offers', async function () {
      let bad = [];
      bad[1] = [nftToken1.address, 0, 500, user3];
      bad[2] = [nftToken1.address, 10, 500, user3];
      bad[3] = [market.address, 0, 500, user3];

      let err = [];
      err[1] = "Bid too low";
      err[2] = "Token not on market";
      err[3] = "Token not on market";
      await payToken2.approve(market.address, 10000, {from: user3});
      await payToken1.approve(market.address, 5000, {from: user3});
      
      let thrownError;

      for (let i = 1; i < 4; i++) {
        try {
        await market.bid(bad[i][0], bad[i][1], bad[i][2], {from: bad[i][3]});
        } catch(error) {
          thrownError = error;
        }
        assert.include(thrownError.message, err[i]);
      }
    });

    it('bid standard offer', async function () {
      let thrownError;
      //offer[1] = [nftToken1.address, payToken1.address, 0, 600, 0, 1, startTime + week, user3] // user1 token 1/0 ; auction
      // bid under price, bid properly, bid again, bid and win, bid ended

      // bid under price
      await payToken1.approve(market.address, 5000, {from: user3});
      try {
        await market.bid(nftToken1.address, 0, 100, {from: user3});      
      } catch(error) {
        thrownError = error;
      }
      assert.include(thrownError.message, "Bid too low");

      // bid properly
      await payToken1.approve(market.address, 5000, {from: user3});
      ret = await market.bid(nftToken1.address, 0, 600, {from: user3});
      logGas(ret, "market.bid 1")
      expectEvent(ret,"BidMade",{})

      // bid again
      await payToken1.approve(market.address, 5000, {from: user3});
      ret = await market.bid(nftToken1.address, 0, 700, {from: user3});
      expectEvent(ret,"BidMade",{})
      let initialBalance = await payToken1.balanceOf(user3);

      // bid and win
      await payToken1.approve(market.address, 5000, {from: user3});
      ret = await market.bid(nftToken1.address, 0, 1000, {from: user3});
      expectEvent(ret,"BidMade",{})

      //verify, that tokens/eth are sent back to loser
      let balance = await payToken1.balanceOf(user3);
      assert.equal(parseInt(balance), parseInt(initialBalance) + 700 - 1000);
      
      // bid ended
      await payToken1.approve(market.address, 5000, {from: user3});
      try {
        await market.bid(nftToken1.address, 0, 1100, {from: user3});      
      } catch(error) {
        thrownError = error;
      }
      assert.include(thrownError.message, "Too late");
    })

    it('buy-now', async function () {
      //offer[4] = [nftToken2.address, payToken2.address, 1, 5000, 0, 0, 0, user2]  // user2, token 2/1 ; buy-now
      // bid under price, bid over price, bid properly, bid again ended
      let thrownError;
      // bid under price
      await payToken2.approve(market.address, 10000, {from: user3});
      try {
        await market.bid(nftToken2.address, 1, 4000, {from: user3});        
      } catch(error) {
        thrownError = error;
      }
      assert.include(thrownError.message, "Need exact value");

      // bid over price
      await payToken2.approve(market.address, 10000, {from: user3});
      try {
        await market.bid(nftToken2.address, 1, 6000, {from: user3});        
      } catch(error) {
        thrownError = error;
      }
      assert.include(thrownError.message, "Need exact value");

      // bid properly
      await payToken2.approve(market.address, 10000, {from: user3});
      ret = await market.bid(nftToken2.address, 1, 5000, {from: user3});
      logGas(ret, "market.bid 2")
      expectEvent(ret,"BidMade",{})

      // bid again ended
      await payToken2.approve(market.address, 10000, {from: user3});
      try {
        await market.bid(nftToken2.address, 1, 5000, {from: user3});        
      } catch(error) {
        thrownError = error;
      }
      assert.include(thrownError.message, "Too late");
    })

    it('bid and buy-now', async function () {
      //offer[3] = [nftToken2.address, ZERO_ADDRESS, 0, 300, 30000, 10, startTime + (day * 10), user1]  // user1, token 2/0; ETH auction+buy-now
      // bid under price, bid over price, bid properly, bid and win, bid ended
      let thrownError;
      
      //bid under price
      await payToken2.approve(market.address, 2000, {from: user3});
      try {
        await market.bid(nftToken2.address, 0, 200, {from: user3, value: 200});
      } catch(error) {
        thrownError = error;
      }
      assert.include(thrownError.message, "Bid too low");

      //bid over price
      // await payToken2.approve(market.address, 50000, {from: user3});
      // try {
      //  await market.bid(nftToken2.address, 0, 31000, {from: user3, value: 31000});
      // } catch(error) {
      //   thrownError = error;
      // }
      // assert.include(thrownError.message, "Bid too low");

      //bid properly
      await payToken2.approve(market.address, 2000, {from: user3});
      ret = await market.bid(nftToken2.address, 0, 1000, {from: user3, value: 1000});
      logGas(ret, "market.bid 3")
      expectEvent(ret,"BidMade",{})

      //bid and win
      await payToken2.approve(market.address, 50000, {from: user3});
      await market.bid(nftToken2.address, 0, 30000, {from: user3, value: 30000});
      expectEvent(ret,"BidMade",{})

      //bid again ended
      // await payToken2.approve(market.address, 50000, {from: user3});
      // try {
      //  await market.bid(nftToken2.address, 0, 20000, {from: user3, value: 20000});
      // } catch(error) {
      //   thrownError = error;
      // }
      // assert.include(thrownError.message, "Too late");
    })
  })

  describe('resell', function () {
    //offer[5] = [nftToken2.address, payToken2.address, 3, 2000, 0, 0, 0, user2]  // user2, token 2/1 ; buy-now
    it('throws badly configured offers', async function () {
      let bad = [];
      bad[1] = [nftToken1.address, payToken2.address, 1, 500, 0, 5, 0, user2] 
      bad[2] = [nftToken2.address, payToken2.address, 1, 5000, 0, 0, startTime + months2, user2]
      bad[3] = [nftToken2.address, payToken2.address, 1, 1000, 500, 0, 0, user2]
      bad[4] = [nftToken2.address, user2, 1, 500, 1000, 0, 0, user2]
      bad[5] = [nftToken2.address, payToken2.address, 1, 500, 1000, 0, 0, user1]
      let err = [];
      err[1] = "Too early";
      err[2] = "Wrong timestamp set"
      err[3] = "MaxPrice below price"
      err[4] = "Wrong payment token"
      err[5] = "It's not yours"

      await nftToken2.setOperator(market.address, { from: user2 })
      await nftToken1.setOperator(market.address, { from: user2 })

      for (let i = 1; i < 6; i++) {
        await expectRevert(market.resell(bad[i][1], bad[i][0], bad[i][2], bad[i][3], bad[i][6], bad[i][5], bad[i][4], { from: bad[i][7] }), err[i])
      }
    })

    it('resell as owner', async function () {
      let offer = [];
      offer[0] = [nftToken2.address, payToken2.address, 3, 5000, 30000, 10, startTime + weeks2, user2]  
      ret = await market.resell(offer[0][1], offer[0][0], offer[0][2], offer[0][3], offer[0][6], offer[0][5], offer[0][4], { from: offer[0][7] })
      logGas(ret, "market.resell")
    })

    it('resell as winner', async function () {
      let offer = [];
      offer[0] = [nftToken2.address, payToken2.address, 1, 5000, 30000, 10, startTime + weeks2, user3]  // user2, token 2/1 ; buy-now
      ret = await market.resell(offer[0][1], offer[0][0], offer[0][2], offer[0][3], offer[0][6], offer[0][5], offer[0][4], { from: offer[0][7] })
      logGas(ret, "market.resell")
    })
  })
  
  describe('claim', function () {
    // claim as winner, claim as owner, claim not yours, claim again yours, claim not bidden
    it('claim not yours', async function () {
      for (let i = 1; i < 4; i++) {
        try {
        await market.claim(nftToken2.address, 1, {from: user4});
        } catch(error) {
          thrownError = error;
        }
        assert.include(thrownError.message, "It's not yours");
      }
    })

    it('claim not bidden', async function () {
      let bad = [];
      bad[1] = [nftToken2.address, 10, user2];
      bad[2] = [market.address, 1, user2];

      let err = [];
      err[1] = "Token not on market";
      err[2] = "Token not on market";
      await payToken2.approve(market.address, 10000, {from: user2});
      await payToken1.approve(market.address, 5000, {from: user2});
      
      let thrownError;

      for (let i = 1; i < 4; i++) {
        try {
        await market.claim(bad[i][0], bad[i][1], {from: bad[i][2]});
        } catch(error) {
          thrownError = error;
        }
        assert.include(thrownError.message, err[i]);
      }
    });

    it('claim as winner', async function () {
      let offer = [];
      let initialOfferCount = await market.getOffersCount();
      offer[1] = [nftToken1.address, payToken1.address, 0, 600, 0, 1, startTime + week, user3]
      //offer[1] = [nftToken1.address, payToken1.address, 0, 500, 0, 1, startTime + week, user1];
      ret = await market.claim(offer[1][0], offer[1][2], {from: offer[1][7]});
      logGas(ret, "market.claim")
      assert.equal(await market.getOffersCount(), parseInt(initialOfferCount) - 1);
    })

    it('claim as owner', async function () {
      let offer = [];
      let initialOfferCount = await market.getOffersCount();
      offer[1] = [nftToken1.address, payToken1.address, 1, 5000, 0, 1, startTime + week, user2];
      //offer[1] = [nftToken1.address, payToken1.address, 0, 500, 0, 1, startTime + week, user1];
      ret = await market.claim(offer[1][0], offer[1][2], {from: offer[1][7]});
      logGas(ret, "market.claim")
      assert.equal(await market.getOffersCount(), parseInt(initialOfferCount) - 1);
    })

    it('claim again yours', async function () {
      let offer = [];
      let initialOfferCount = await market.getOffersCount();
      offer[1] = [nftToken1.address, payToken1.address, 1, 5000, 0, 1, startTime + week, user2];
      //offer[1] = [nftToken1.address, payToken1.address, 0, 500, 0, 1, startTime + week, user1];
      let thrownError;

      try {
        await market.claim(offer[1][0], offer[1][2], {from: offer[1][7]});
      } catch(error) {
        thrownError = error;
      }
      assert.include(thrownError.message, "Token not on market");
    })
  })

  describe('withdrawMarketFee', async function () {
    it('not working if nothing to withdraw', async function () {
      let thrownError;

      try {
        await market.withdrawMarketFee(payToken3.address);
      } catch(error) {
        thrownError = error;
      }
      assert.include(thrownError.message, "Nothing to withdraw");
    })

    it('Works fine with normal flow', async function () {
      let feeCollected = await market.getFeeCollected(payToken1.address);
      let initialBal = await payToken1.balanceOf(market.address);
      let ret = await market.withdrawMarketFee(payToken1.address);
      logGas(ret, "market.withdrawMarketFee");
      assert.equal(await payToken1.balanceOf(market.address), parseFloat(initialBal) - parseFloat(feeCollected))
    })
  })

  describe('readers', async function(){
    it('getOfferBytoken', async function () {
      let offer1 = await market.getOfferByToken(nftToken2.address, 0);
      assert.equal(offer1.paymentToken, ZERO_ADDRESS);
      assert.equal(offer1.price, 30000);
      assert.equal(offer1.maxPrice, 30000);
      assert.equal(offer1.minStep, 10);
    })

    it('getMiniumBid', async function () {
      let minimumBid = await market.getMiniumBid(nftToken2.address, 0);
      assert.equal(minimumBid, 30010);
    })

    it('getAllOffers', async function () {
      let offers = await market.getAllOffers();
      assert.equal(offers.length, await market.getOffersCount());
    })

    it('getOffersCount', async function () {
      let thrownError;

      let offersCount = await market.getOffersCount();
      try {
        await market.getOffersOfByRange(user2, 2, parseInt(offersCount) + 5);
      } catch(error) {
        thrownError = error;
      }
      assert.include(thrownError.message, "End over length");
    })

    it('getBidsOf', async function () {
      let bids = await market.getBidsOf(user2);
      assert.equal(bids.length, await market.getBidsCount(user2));
    })

    it('mock 20 offers', async function () {
      //offer[1] = [nftToken1.address, payToken1.address, 0, 500, 1000, 1, startTime + week, user1] // user1 token 1/0 ; auction
      await nftToken1.setOperator(market.address, { from: user1 })
      for(let i = 0; i < 10; i++) {
        await market.sell(nftToken1.address, payToken1.address, i + 3, 0, 0, 0, 0, { from: user2 })
        await market.sell(nftToken2.address, payToken2.address, i + 4, 0, 0, 0, 0, { from: user1 })
      }
    })

    it('getOffersByRange', async function () {
      let offersCount = await market.getOffersCount();
      
      //return proper data
      await market.getOffersByRange(2, parseInt(offersCount) -1);

      // out-of-range
      let thrownError;

      try {
        await market.getOffersByRange(2, parseInt(offersCount) + 5);
      } catch(error) {
        thrownError = error;
      }
      assert.include(thrownError.message, "End over length");
    })

    it('getOffersOfByRange', async function () {
      let offersCount = await market.getOffersCountByUser(user2);
      
      //return proper data
      await market.getOffersOfByRange(user2, 0, parseInt(offersCount) -1);

      // out-of-range
      let thrownError;

      try {
        await market.getOffersOfByRange(user2, 2, parseInt(offersCount) + 5);
      } catch(error) {
        thrownError = error;
      }
      assert.include(thrownError.message, "End over length");
    })

    it('getBidsByRange', async function () {
      let bidsCount = await market.getBidsCount(user3);

      // out-of-range
      let thrownError;
      try {
        await market.getBidsByRange(user1, 0, parseInt(bidsCount) + 5);
      } catch(error) {
        thrownError = error;
      }
      assert.include(thrownError.message, "Range length error");
    })
  })
})

describe('Gas usage log', function () {
  it('logs gas usage', async function () {
    for (var i = 0; i < gasUsage.length; i++) {
      console.log('\tfunction:', gasUsage[i].name, '\t:', gasUsage[i].value)
    }
  })
})
