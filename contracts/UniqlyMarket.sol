// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
import "./Ierc721.sol";
import "./Owned.sol";
import "./Ierc20.sol";

// TODO: reader: all offers by NFT token type
// TODO: reader: all offers by payment token type
// TODO: reader: all offers that have bid?
// TODO: verify royalty percentage calc

/**
@title Market contract for NFT tokens
@notice sell - put token on market from start price to given timestamp
@notice bid - place bid on token
@notice claim - claim won token or reclaim if no offers, pay seller
@notice resell - put token on market again (as owner - if no offers, or as winner)
 */
contract UniqlyMarket is Owned {
    address constant ZERO = address(0);

    // maximum time that offer can be bidden
    uint256 immutable maxTime;

    // time that every bid moving end of auction
    uint256 immutable prolongOffer;
    /// protect external ETH payouts from re-entry
    bool internal running;

    /**
    @param maxOfferTime time in seconds for max offer bidding time
    @param offerProlong time in seconds when bid is prolonging offer
     */
    constructor(uint256 maxOfferTime, uint256 offerProlong) {
        owner = msg.sender;
        maxTime = maxOfferTime;
        prolongOffer = offerProlong;
    }

    /**
    tokenId - token ID
    price - current price
    date - end of bidding
    bidder - best bid
    owner - offer maker
    token - address of NFT token
     */
    struct Offer {
        address nftToken;
        address paymentToken;
        address seller;
        address buyer;
        uint256 tokenId;
        uint256 endDate;
        uint256 price;
        uint256 minStep;
        uint256 maxPrice;
    }

    // order book
    Offer[] internal offers;

    // token-> offer indexer
    // NFT->tokenId->offer
    mapping(address => mapping(uint256 => uint256)) token2offer;

    // possible NFT tokens
    mapping(address => bool) _nftTokens;

    // accepted payment ERC20 tokens 0x0 is ETH
    mapping(address => bool) _paymentToken;

    // market fee when using payment token 0-10% as 10^4 value 1%=10000
    mapping(address => uint256) _marketFee;
    mapping(address => uint256) _feesAvailable;

    // error strings
    string internal constant ERR_TOOEARLY = "Too early";
    string internal constant ERR_SOLD = "Sold already";
    string internal constant ERR_NOTUR = "It's not yours";
    string internal constant ERR_TOOLONG = "Wrong timestamp set";
    string internal constant ERR_XACK = "Hax failed";
    string internal constant ERR_TRANSFER = "Token transfer error";
    string internal constant ERR_MAXPRICE = "MaxPrice below price";
    string internal constant ERR_WRONGPT = "Wrong payment token";
    string internal constant ERR_ENDTOOHIGH = "End over length";

    // offer state change counter
    uint256 internal _counter;

    //events
    event OfferAdded(
        address indexed token,
        address indexed seller,
        uint256 indexed tokenId,
        uint256 price,
        uint256 deadline
    );
    event BidMade(
        address indexed token,
        address indexed buyer,
        uint256 indexed tokenId,
        uint256 price
    );

    event Sold(
        address owner,
        address token,
        uint256 tokenId,
        address paymentToken,
        uint256 price
    );
    event TransferToMarket(address indexed token, uint256 indexed tokenId);
    event TransferFromMarket(address indexed token, uint256 indexed tokenId);

    /**
    @notice place token on market
    @dev need approve this contract first, preferably by "approve for all"
    @dev test added
    @param nftToken NFT token contract address
    @param paymentToken accepted payment token
    @param tokenId NFT token ID
    @param price start/current price
    @param maxPrice max price if "auction with buy-now" (or 0 if no limit)
    @param minStep minimum auction step
    @param date timestamp to end auction (or 0 if "sell now")
     */
    function sell(
        address nftToken,
        address paymentToken,
        uint256 tokenId,
        uint256 price,
        uint256 maxPrice,
        uint256 minStep,
        uint256 date
    ) external {
        require(_nftTokens[nftToken], "Wrong NFT token address");
        require(_paymentToken[paymentToken], ERR_WRONGPT);
        require(token2offer[nftToken][tokenId] == 0, "Token already on market");

        if (date != 0) {
            // auction
            require(minStep > 0, "MinStep not set");

            require(
                date > block.timestamp && date < block.timestamp + maxTime,
                ERR_TOOLONG
            );
        } else {
            // buy-now
            require(minStep == 0, "MinStep set");
            require(maxPrice == 0, "MaxPrice set");
        }
        if (maxPrice > 0) {
            // auction + buy-now roof price
            require(maxPrice > price, ERR_MAXPRICE);
        }
        offers.push(
            Offer(
                nftToken,
                paymentToken,
                msg.sender,
                ZERO,
                tokenId,
                date,
                price,
                minStep,
                maxPrice
            )
        );
        token2offer[nftToken][tokenId] = offers.length; //yep, +1, as 0 is bad xD
        emit OfferAdded(nftToken, msg.sender, tokenId, price, date);
        _counter++;
        //transfer NTF to contract, will fail if no approval
        _transfer(nftToken, msg.sender, address(this), tokenId);
    }

    /**
    @dev ensure that token is on market
    @dev test not added because of modifier
    @param token NFT contract address
    @param id token ID
    */
    modifier onMarket(address token, uint256 id) {
        require(token2offer[token][id] != 0, "Token not on market");
        _;
    }

    /// protect payment functions from re-entering
    /// @dev test not added because of modifier
    modifier noReenter() {
        require(!running, ERR_XACK);
        running = true;
        _;
        running = false;
    }

    /**
    @notice place bid on offer
    @dev bid value is ETH by msg.value
    @dev test added
    @param token NFT address
    @param id token id
    **/
    function bid(
        address token,
        uint256 id,
        uint256 value
    ) external payable onMarket(token, id) noReenter {
        uint256 ts = block.timestamp;

        Offer storage o = offers[token2offer[token][id] - 1];

        if (o.paymentToken == ZERO) {
            require(msg.value == value, "Bad ETH value send");
        } else {
            require(
                Ierc20(o.paymentToken).transferFrom(
                    msg.sender,
                    address(this),
                    value
                ),
                ERR_TRANSFER
            );
        }

        if (o.endDate == 0) {
            require(value == o.price, "Need exact value");
            o.endDate = 1; //mark as sold
        } else {
            if (o.maxPrice > 0 && value == o.maxPrice) {
                // someone hit the roof
                o.endDate = 1; // SOLD
            } else {
                require(value >= o.price + o.minStep, "Bid too low");
                require(ts < o.endDate, "Too late");
                // when time is ending we make it go longer
                // also double minimum auction step
                if (ts + prolongOffer > o.endDate) {
                    o.endDate += prolongOffer;
                    o.minStep += o.minStep;
                }
            }
        }
        address last = o.buyer;
        uint256 amt = o.price;
        o.buyer = msg.sender;
        o.price = value;
        // pay loser back his bid
        if (last != ZERO) {
            _safeTransfer(last, o.paymentToken, amt);
        }
        emit BidMade(token, msg.sender, id, value);
        _counter++;
    }

    /**
    @notice claim token from market
    @dev won on auction or claim back by owner if no bets made
    @dev test added
    @param nft NTF token address
    @param id token ID to be claimed
    **/
    function claim(address nft, uint256 id) external onMarket(nft, id) {
        Offer storage o = offers[token2offer[nft][id] - 1];

        address dest; // who will take NFT

        //claim by winner
        if (o.buyer == msg.sender) {
            require(block.timestamp > o.endDate, ERR_TOOEARLY);
            dest = msg.sender;
        }
        //claim by owner at any time
        else if (o.seller == msg.sender) {
            // if no offers take back token
            dest = o.buyer == ZERO ? msg.sender : o.buyer;
        }
        //no one else can claim
        else {
            revert(ERR_NOTUR);
        }

        // sell happened, payment token handling: pay seller, royalty, market fee
        if (dest == o.buyer) {
            _claim(o);
        }

        // remove offer from market
        if (offers.length > 1) {
            offers[token2offer[nft][id] - 1] = offers[offers.length - 1];
        }
        offers.pop();
        delete token2offer[nft][id];

        // send  token to new owner
        _transfer(nft, address(this), dest, id);
        _counter++;
    }

    /**
    @dev test not added because this function is tested while testing claim function
    @notice internal claim function, pay seller and royalty
    @param o storage offer to claim
     */
    function _claim(Offer storage o) internal noReenter {
        uint256 id = o.tokenId;
        uint256 val = o.price;
        address own = o.seller;
        address nft = o.nftToken;
        address pay = o.paymentToken;

        address roy;
        uint256 royalty;
        try Ierc721(nft).royaltyInfo(id) returns (address who, uint256 much) {
            roy = who;
            royalty = much;
        } catch {}

        uint256 marketFee = _marketFee[pay];

        if (marketFee > 0) {
            uint256 fee = (val * marketFee) / 1000000; // 10^4 %
            _feesAvailable[pay] += fee;
            val -= fee; // fee stays on market
        }

        uint256 v;
        if (royalty > 0 && roy != ZERO) {
            v = (val * royalty) / 10000; //TODO real value
            _safeTransfer(roy, pay, v); // send royalty fee
            try
                Ierc721(nft).receivedRoyalties(roy, msg.sender, id, pay, v)
            {} catch {} //inform contract if possible
        }
        val -= v;
        _safeTransfer(own, pay, val); //pay seller minus royalty fee
        emit Sold(own, nft, id, pay, val);
    }

    /**
    @notice resell token on market w/o claiming it
    @dev test added
    @dev can be used by owner (if no offers) or winner (when bid ends)
    @param paymentToken new payment token
    @param nft NFT token address
    @param id tokenID
    @param price of new offer (in wei)
    @param date timestamp that end auction
    @param minStep new auction step
    @param maxPrice new max price
    **/
    function resell(
        address paymentToken,
        address nft,
        uint256 id,
        uint256 price,
        uint256 date,
        uint256 minStep,
        uint256 maxPrice
    ) external onMarket(nft, id) {
        Offer storage o = offers[token2offer[nft][id] - 1];
        uint256 ct = block.timestamp;
        require(ct > o.endDate, ERR_TOOEARLY);
        // date=0 -> quick sell
        require(date == 0 || (date > ct && date < ct + maxTime), ERR_TOOLONG);
        // maxPrice>0 - auction with buy-now option
        if (maxPrice > 0) {
            require(maxPrice > price, ERR_MAXPRICE);
        }
        // you can pick payment only form approved tokens
        require(_paymentToken[paymentToken], ERR_WRONGPT);

        // owner can set it back to market if no bids
        if (o.buyer == ZERO) {
            require(o.seller == msg.sender, ERR_NOTUR);
        }
        // winner can put on market instead of claiming
        else if (o.buyer == msg.sender) {
            _claim(o);
            o.seller = msg.sender;
            o.buyer = ZERO;
        } else revert(ERR_NOTUR);

        o.endDate = date;
        o.price = price;
        o.maxPrice = maxPrice;
        o.paymentToken = paymentToken;
        o.minStep = minStep;
        emit OfferAdded(nft, msg.sender, id, price, date);
        _counter++;
    }

    //
    // getters
    //

    /// how many offers is on market
    /// can be used for paging
    /// @return number of offers
    /// @dev tested while testing other functions
    function getOffersCount() external view returns (uint256) {
        return offers.length;
    }

    /// get single offer by its index
    /// @return single offer struct
    /// @dev test not added because getOfferIdx function not exist
    function getOfferByIndex(uint256 idx) external view returns (Offer memory) {
        return offers[idx];
    }

    /**
    get current minimum bid on offer
    @dev test added
    @param nft NFT token address
    @param id NTF token index
    @return minimum price in offer token
    */
    function getMiniumBid(address nft, uint256 id)
        external
        view
        returns (uint256)
    {
        Offer memory o = offers[token2offer[nft][id] - 1];
        return o.price + o.minStep;
    }

    /// offer state change counter reader
    function getCounter() external view returns (uint256) {
        return _counter;
    }

    /**
    get single offer for given NFT/tokenID
    @dev test added
    @param nft token address
    @param id token index
    @return single Offer struct
    */
    function getOfferByToken(address nft, uint256 id)
        external
        view
        returns (Offer memory)
    {
        return offers[token2offer[nft][id] - 1];
    }

    /// List all offers on market
    /// better use paging (count + range)
    /// @dev test added
    /// @return array of offers
    function getAllOffers() external view returns (Offer[] memory) {
        //copy storage
        uint256 ol = offers.length;
        if (ol > 0) {
            Offer[] memory o = new Offer[](ol);
            uint256 i;
            for (i; i < ol; i++) {
                o[i] = offers[i];
            }
            return o;
        } else return new Offer[](0);
    }

    /**
    @notice get offers from market by index range from-to
    @dev test added
    @param start start index of listing
    @param end end index of listing
    @return array of Offer objects
    */
    function getOffersByRange(uint256 start, uint256 end)
        external
        view
        returns (Offer[] memory)
    {
        if (start > end) (start, end) = (end, start); //swap if necessary
        require(end < offers.length, ERR_ENDTOOHIGH);
        uint256 len = end - start + 1;
        Offer[] memory ret = new Offer[](len);
        uint256 i;
        for (i; i < len; i++) {
            ret[i] = offers[start + i];
        }
        return ret;
    }

    /// list all offers from seller
    /// @dev test added
    /// @param user address of user
    /// @return array of offers
    function getOffersOf(address user) external view returns (Offer[] memory) {
        uint256[] memory list = _offers(user);
        uint256 c = list.length;
        if (c > 0) {
            Offer[] memory ret = new Offer[](c);
            uint256 i;
            for (i; i < c; i++) {
                ret[i] = offers[list[i]];
            }
            return ret;
        } else return new Offer[](0);
    }

    /**
    @dev test not added because It occur some errors when call this function on test
    @notice get number of offers set by seller
    @param user seller/owner address
    @return number of offers
    */
    function getOffersCountByUser(address user)
        external
        view
        returns (uint256)
    {
        return _offersCount(user);
    }

    // internal count of offers
    // this can be avoided by adding additional mapping
    // but it would cost gas - readers are for free
    /// @dev test not added because of internal function
    function _offersCount(address user) internal view returns (uint256 count) {
        uint256 len = offers.length;
        uint256 i;
        for (i; i < len; i++) {
            if (offers[i].seller == user) {
                count++;
            }
        }
    }

    // internal search for user offers
    // need iterate entire market
    // but its free
    /// @dev test not added because of internal function
    function _offers(address user) internal view returns (uint256[] memory) {
        uint256 c = _offersCount(user);
        if (c > 0) {
            uint256[] memory list = new uint256[](c);
            c = 0; // reuse counter
            uint256 i;
            uint256 len = offers.length;
            for (i; i < len; i++) {
                if (offers[i].seller == user) {
                    list[c] = i;
                    c++;
                }
            }
            return list;
        } else return new uint256[](0);
    }

    /**
    @notice return user offers by index range
    @notice needed for large sellers
    @dev test added
    @param user address of user
    @param start index of his start offer
    @param end index of his end offer
    */
    function getOffersOfByRange(
        address user,
        uint256 start,
        uint256 end
    ) external view returns (Offer[] memory) {
        if (start > end) (start, end) = (end, start); //swap if necessary
        uint256[] memory list = _offers(user);
        uint256 c = list.length;
        require(end < c, ERR_ENDTOOHIGH);
        uint256 len = end - start + 1;
        Offer[] memory ret = new Offer[](len);
        uint256 i;
        for (i; i < len; i++) {
            ret[i] = offers[list[start + i]];
        }
        return ret;
    }

    /// list all offers that user has currently winning bid
    /// call with 0x0 would get all offers w/o bids
    /// but it can be too large array, use paging
    /// @dev test added
    function getBidsOf(address user) external view returns (Offer[] memory) {
        uint256[] memory tmp = _bids(user);
        uint256 n = tmp.length;
        if (n > 0) {
            uint256 i;
            Offer[] memory out = new Offer[](n);
            for (i; i < n; i++) {
                out[i] = offers[tmp[i]];
            }
            return out;
        } else return new Offer[](0); //nothing found
    }

    /**
    @notice get count of winning bids
    @notice then usee getter for all or index
    @dev test not added because this function is tested by testing getBidsOf
    @param user address of buyer to count
    @return count of wining bids
    */
    function getBidsCount(address user) external view returns (uint256) {
        return _bidsCount(user);
    }

    /**
    @notice get winning offers by index, useful for fetching all offers w/o bids
    @notice just ask for 0x0
    @dev test added
    @param user address of winner
    @param start start index of his bets
    @param end end index of his best
    @return array of offers
    */
    function getBidsByRange(
        address user,
        uint256 start,
        uint256 end
    ) external view returns (Offer[] memory) {
        if (start > end) (start, end) = (end, start); //swap if necessary
        uint256[] memory tmp = _bids(user);
        uint256 c = tmp.length;
        uint256 len = end - start + 1;
        require(len < c, "Range length error");
        if (c > 0) {
            uint256 i;
            Offer[] memory ret = new Offer[](c);
            for (i; i < c; i++) {
                ret[i] = offers[tmp[i]];
            }
            return ret;
        } else return new Offer[](0);
    }

    // internal counter of winning bids
    // could be avoided by adding additional mapping
    // but that would cost gas on every bid
    // readers are free
    /// @dev test not added because of internal function
    function _bidsCount(address user) internal view returns (uint256 count) {
        uint256 len = offers.length;
        uint256 i;
        // count winning bids
        for (i; i < len; i++) {
            if (offers[i].buyer == user) {
                count++;
            }
        }
    }

    // return all winning bids by user
    // could be done via indexes
    // but it would cost gas on sell/bid
    // readers are free
    /// @dev test not added because of internal function
    function _bids(address user) internal view returns (uint256[] memory) {
        uint256 n = _bidsCount(user);
        if (n > 0) {
            uint256[] memory tmp = new uint256[](n);
            n = 0; //reuse counter
            uint256 len = offers.length;
            uint256 i;
            // count winning bids
            for (i; i < len; i++) {
                if (offers[i].buyer == user) {
                    tmp[n] = i;
                    n++;
                }
            }
            return tmp;
        } else return new uint256[](0);
    }

    //
    // internal functions
    //

    // call ERC721 transfer function to get/send tokens
    /// @dev test not added because copy of standard
    function _transfer(
        address token,
        address from,
        address to,
        uint256 tokenId
    ) internal {
        Ierc721(token).transferFrom(from, to, tokenId);
        if (from == address(this)) emit TransferFromMarket(token, tokenId);
        else if (to == address(this)) emit TransferToMarket(token, tokenId);
    }

    /// Transfer ERC20 or ETH in "gas-safe" way
    /// @dev test not added because copy of standard
    function _safeTransfer(
        address target,
        address token,
        uint256 amt
    ) internal {
        if (token == ZERO) {
            (bool success, ) = target.call{value: amt}("");
            require(success, "ETH transfer failed.");
        } else {
            require(Ierc20(token).transfer(target, amt), ERR_TRANSFER);
        }
    }

    //
    // god mode
    //

    /// @dev test not added because this function is tested while initializing
    function addNftToken(address token) external onlyOwner {
        _nftTokens[token] = true;
    }

    /// @dev test not added because not get function
    function removeNftToken(address token) external onlyOwner {
        _nftTokens[token] = false;
    }

    /// @dev test not added because this function is tested while initializing
    function addPaymentToken(address token, uint256 marketFee)
        external
        onlyOwner
    {
        _paymentToken[token] = true;
        _marketFee[token] = marketFee;
    }

    /// @dev test not added because not get function
    function removePaymentToken(address token) external onlyOwner {
        delete _paymentToken[token];
        delete _marketFee[token];
    }

    /// @dev test not added because this function is tested while testing withdrawMarketFee function
    function getFeeCollected(address token) external view returns (uint256) {
        return _feesAvailable[token];
    }

    /// @dev test added
    function withdrawMarketFee(address token) external onlyOwner {
        uint256 amt = _feesAvailable[token];
        require(amt > 0, "Nothing to withdraw");
        _feesAvailable[token] = 0;
        _safeTransfer(owner, token, amt);
    }

    /**
    Witchdraw market fee by owner signature
    @param token payment token address
    @param amount amount of payment token to withdraw
    @param r part of signature
    @param s part of signature
    @param v part of signature
    */
    function withdrawFee(
        address token,
        uint256 amount,
        bytes32 r,
        bytes32 s,
        uint8 v
    ) external {
        uint256 amt = _feesAvailable[token];
        require(amount < amt, "Wrong amount");
        bytes32 data = keccak256(
            abi.encodePacked(msg.sender, token, amount, address(this))
        );
        address signer = ecrecover(data, v, r, s);
        require(signer == owner, "Bad signature");
        _feesAvailable[token] -= amount;
        _safeTransfer(msg.sender, token, amount);
    }

    /**
    Get all market offers that have bid
    Can fail on big market, use indexed reader instead in that case
    @return Offer[] struct
    */
    function getBiddingOffers() external view returns (Offer[] memory) {
        uint256 size = _biddingOffersCount();
        uint256 cnt;
        uint256 len = offers.length;
        uint256 i;
        Offer[] memory ret = new Offer[](size);
        for (i; i < len; i++) {
            Offer memory o = offers[i];
            if (o.buyer != ZERO) {
                ret[cnt] = o;
                cnt++;
            }
            if (cnt == size) break;
        }
        return ret;
    }

    /// Return number of offers on market that have any bid, for indexed reader
    function getBiddingOffersCount() external view returns (uint256) {
        return _biddingOffersCount();
    }

    function _biddingOffersCount() internal view returns (uint256) {
        uint256 cnt;
        uint256 len = offers.length;
        uint256 i;
        for (i; i < len; i++) {
            if (offers[i].buyer != ZERO) cnt++;
        }
        return cnt;
    }

    /**
    Get all market offers that have bid by index range
    @param start index
    @param end index
    @return Offer[] struct
    */
    function getBiddingOffersByIndex(uint256 start, uint256 end)
        external
        view
        returns (Offer[] memory)
    {
        uint256 olen = _biddingOffersCount();
        require(end >= start && end < olen, "Range error");
        uint256 len = offers.length;
        Offer[] memory ret = new Offer[](end - start + 1);
        uint256 ocnt; // bidden offers counter
        uint256 cnt; // selected offers counter
        uint256 i;
        for (i; i < len; i++) {
            Offer memory o = offers[i];
            if (o.buyer != ZERO) {
                if (ocnt <= start && ocnt >= end) {
                    ret[cnt] = o;
                    cnt++;
                }
                ocnt++;
            }
            if (cnt == ret.length) break; // found enough
        }
        return ret;
    }

    /**
    Get all market offers using given payment token
    Can fail on big markets, use indexed view in that case
    @param token payment token address
    @return Offer[] struct
    */
    function getOffersByPaymentToken(address token)
        external
        view
        returns (Offer[] memory)
    {
        uint256 size = _offersByPaymetCount(token);
        Offer[] memory ret = new Offer[](size);
        uint256 len = offers.length;
        uint256 cnt;
        uint256 i;
        for (i; i < len; i++) {
            Offer memory o = offers[i];
            if (o.paymentToken == token) {
                ret[cnt] = o;
                cnt++;
            }
            if (cnt == size) break;
        }
        return ret;
    }

    /**
    Get count of offers that use given payment token
    @param token address of payment token
    @return count of offers
    */
    function getOffersByPaymentTokenCount(address token)
        external
        view
        returns (uint256)
    {
        return _offersByPaymetCount(token);
    }

    function _offersByPaymetCount(address token)
        internal
        view
        returns (uint256)
    {
        uint256 len = offers.length;
        uint256 cnt;
        uint256 i;
        for (i; i < len; i++) {
            if (offers[i].paymentToken == token) cnt++;
        }
        return cnt;
    }

    /**
    Get offers by payment token - indexed
    @param token address of payment token
    @param start index of offer on this payment token
    @param end index of offer on this payment token
    @return Offer[] array
     */
    function getOffersByPaymentToken(
        address token,
        uint256 start,
        uint256 end
    ) external view returns (Offer[] memory) {
        uint256 max = _offersByPaymetCount(token);
        require(start <= end && end < max, "Range error");
        uint256 ocnt;
        uint256 cnt;
        uint256 i;
        Offer[] memory ret = new Offer[](end - start + 1);
        uint256 len = offers.length;
        for (i; i < len; i++) {
            Offer memory o = offers[i];
            if (o.paymentToken == token) {
                if (ocnt <= end && ocnt >= start) {
                    ret[cnt] = o;
                    cnt++;
                }
                ocnt++;
            }
            if (cnt == ret.length) break;
        }
        return ret;
    }

    /**
    Get count of offers that use NTF token
    @param token NFT address
    @return number of offers
    */
    function getOffersByTokenCount(address token)
        external
        view
        returns (uint256)
    {
        return _offersByTokenCount(token);
    }

    function _offersByTokenCount(address token)
        internal
        view
        returns (uint256)
    {
        uint256 len = offers.length;
        uint256 cnt;
        uint256 i;
        for (i; i < len; i++) {
            if (offers[i].nftToken == token) {
                cnt++;
            }
        }
        return cnt;
    }

    /**
    Get all offers on market by NFT token address
    Can fail on big markets, use indexed viewer instead
    @param token NTF token address
    @return Offer[] array
    */
    function getOffersByToken(address token)
        external
        view
        returns (Offer[] memory)
    {
        uint256 size = _offersByTokenCount(token);
        Offer[] memory ret = new Offer[](size);
        uint256 len = offers.length;
        uint256 cnt;
        uint256 i;
        for (i; i < len; i++) {
            Offer memory o = offers[i];
            if (o.nftToken == token) {
                ret[cnt] = o;
                cnt++;
            }
            if (cnt == size) break;
        }
        return ret;
    }

    /**
    Get offers by NFT token, indexed
    @param token NFT address
    @param start index of offer
    @param end index of offer
    @return Offer[] array
    */
    function getOffersByToken(
        address token,
        uint256 start,
        uint256 end
    ) external view returns (Offer[] memory) {
        uint256 max = _offersByTokenCount(token);
        require(start <= end && end < max, "Range error");
        Offer[] memory ret = new Offer[](end - start + 1);
        uint256 len = offers.length;
        uint256 cnt;
        uint256 ocnt;
        uint256 i;
        for (i; i < len; i++) {
            Offer memory o = offers[i];
            if (o.nftToken == token) {
                if (start >= ocnt && end <= ocnt) {
                    ret[cnt] = o;
                    cnt++;
                }
                ocnt++;
            }
            if (cnt == ret.length) break;
        }
        return ret;
    }
}
