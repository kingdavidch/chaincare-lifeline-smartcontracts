// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title PaymentSystem
 * @dev Smart contract for stablecoin-based payments in ChainCare ecosystem
 * Handles automated claim payouts and patient payments as specified in documentation
 */
contract PaymentSystem is AccessControl, ReentrancyGuard, Pausable {
    
    bytes32 public constant PAYMENT_PROCESSOR_ROLE = keccak256("PAYMENT_PROCESSOR_ROLE");
    bytes32 public constant CLAIMS_CONTRACT_ROLE = keccak256("CLAIMS_CONTRACT_ROLE");
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");

    // Supported stablecoins (USDC, USDT, DAI, etc.)
    mapping(address => bool) public supportedStablecoins;
    mapping(address => string) public stablecoinNames;
    
    // Default stablecoin for payments
    address public defaultStablecoin;

    struct Payment {
        uint256 paymentId;
        address payer;
        address recipient;
        uint256 amount;
        address token;
        string paymentType; // "claim_payout", "premium", "copay", "deductible"
        uint256 claimId; // 0 if not claim-related
        uint256 timestamp;
        bool isCompleted;
        string transactionHash;
        uint256 fees;
    }

    struct EscrowPayment {
        uint256 escrowId;
        address payer;
        address recipient;
        uint256 amount;
        address token;
        uint256 releaseDate;
        bool isReleased;
        bool isCancelled;
        string condition; // "claim_approval", "service_completion", etc.
        uint256 claimId;
    }

    mapping(uint256 => Payment) public payments;
    mapping(uint256 => EscrowPayment) public escrowPayments;
    mapping(address => uint256[]) public userPayments;
    mapping(address => uint256) public totalFeesCollected;
    
    uint256 public paymentCounter;
    uint256 public escrowCounter;
    uint256 public platformFeePercentage = 25; // 0.25% (25/10000)
    address public feeCollector;

    event StablecoinAdded(address indexed token, string name);
    event StablecoinRemoved(address indexed token);
    event PaymentProcessed(
        uint256 indexed paymentId,
        address indexed payer,
        address indexed recipient,
        uint256 amount,
        address token,
        string paymentType
    );
    event ClaimPayoutExecuted(
        uint256 indexed claimId,
        uint256 indexed paymentId,
        address indexed provider,
        uint256 amount
    );
    event EscrowCreated(
        uint256 indexed escrowId,
        address indexed payer,
        address indexed recipient,
        uint256 amount,
        uint256 releaseDate
    );
    event EscrowReleased(uint256 indexed escrowId, uint256 amount);
    event EscrowCancelled(uint256 indexed escrowId);
    event FeesCollected(address indexed token, uint256 amount);

    modifier onlyValidStablecoin(address _token) {
        require(supportedStablecoins[_token], "Stablecoin not supported");
        _;
    }

    modifier onlyValidPayment(uint256 _paymentId) {
        require(payments[_paymentId].paymentId != 0, "Payment does not exist");
        _;
    }

    modifier onlyValidEscrow(uint256 _escrowId) {
        require(escrowPayments[_escrowId].escrowId != 0, "Escrow does not exist");
        _;
    }

    constructor(address _defaultStablecoin, address _feeCollector) {
        require(_defaultStablecoin != address(0), "Invalid stablecoin address");
        require(_feeCollector != address(0), "Invalid fee collector address");
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAYMENT_PROCESSOR_ROLE, msg.sender);
        
        defaultStablecoin = _defaultStablecoin;
        feeCollector = _feeCollector;
        supportedStablecoins[_defaultStablecoin] = true;
        stablecoinNames[_defaultStablecoin] = "USDC";
        
        paymentCounter = 1;
        escrowCounter = 1;
    }

    /**
     * @dev Add a supported stablecoin
     * @param _token Token contract address
     * @param _name Token name for display
     */
    function addStablecoin(address _token, string memory _name) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(_token != address(0), "Invalid token address");
        require(!supportedStablecoins[_token], "Token already supported");
        
        supportedStablecoins[_token] = true;
        stablecoinNames[_token] = _name;
        
        emit StablecoinAdded(_token, _name);
    }

    /**
     * @dev Remove a supported stablecoin
     * @param _token Token contract address
     */
    function removeStablecoin(address _token) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(_token != defaultStablecoin, "Cannot remove default stablecoin");
        require(supportedStablecoins[_token], "Token not supported");
        
        supportedStablecoins[_token] = false;
        delete stablecoinNames[_token];
        
        emit StablecoinRemoved(_token);
    }

    /**
     * @dev Process a general payment
     * @param _recipient Payment recipient
     * @param _amount Payment amount
     * @param _token Stablecoin token address
     * @param _paymentType Type of payment
     * @param _claimId Associated claim ID (0 if not applicable)
     */
    function processPayment(
        address _recipient,
        uint256 _amount,
        address _token,
        string memory _paymentType,
        uint256 _claimId
    ) external nonReentrant whenNotPaused onlyValidStablecoin(_token) {
        require(_recipient != address(0), "Invalid recipient address");
        require(_amount > 0, "Amount must be greater than 0");
        
        IERC20 stablecoin = IERC20(_token);
        require(
            stablecoin.balanceOf(msg.sender) >= _amount,
            "Insufficient balance"
        );
        require(
            stablecoin.allowance(msg.sender, address(this)) >= _amount,
            "Insufficient allowance"
        );

        // Calculate platform fee
        uint256 fee = (_amount * platformFeePercentage) / 10000;
        uint256 netAmount = _amount - fee;

        // Transfer tokens
        require(
            stablecoin.transferFrom(msg.sender, _recipient, netAmount),
            "Transfer to recipient failed"
        );
        
        if (fee > 0) {
            require(
                stablecoin.transferFrom(msg.sender, feeCollector, fee),
                "Fee transfer failed"
            );
            totalFeesCollected[_token] += fee;
        }

        // Record payment
        uint256 paymentId = paymentCounter++;
        payments[paymentId] = Payment({
            paymentId: paymentId,
            payer: msg.sender,
            recipient: _recipient,
            amount: _amount,
            token: _token,
            paymentType: _paymentType,
            claimId: _claimId,
            timestamp: block.timestamp,
            isCompleted: true,
            transactionHash: "",
            fees: fee
        });

        userPayments[msg.sender].push(paymentId);
        userPayments[_recipient].push(paymentId);

        emit PaymentProcessed(paymentId, msg.sender, _recipient, _amount, _token, _paymentType);
    }

    /**
     * @dev Execute claim payout (called by claims contract)
     * @param _claimId Claim ID
     * @param _provider Provider address to pay
     * @param _amount Amount to pay
     * @param _payer Insurance company paying the claim
     */
    function executeClaimPayout(
        uint256 _claimId,
        address _provider,
        uint256 _amount,
        address _payer
    ) external nonReentrant whenNotPaused onlyRole(CLAIMS_CONTRACT_ROLE) {
        require(_provider != address(0), "Invalid provider address");
        require(_payer != address(0), "Invalid payer address");
        require(_amount > 0, "Amount must be greater than 0");

        IERC20 stablecoin = IERC20(defaultStablecoin);
        require(
            stablecoin.balanceOf(_payer) >= _amount,
            "Insufficient balance in payer account"
        );
        require(
            stablecoin.allowance(_payer, address(this)) >= _amount,
            "Insufficient allowance from payer"
        );

        // Calculate platform fee
        uint256 fee = (_amount * platformFeePercentage) / 10000;
        uint256 netAmount = _amount - fee;

        // Transfer tokens
        require(
            stablecoin.transferFrom(_payer, _provider, netAmount),
            "Transfer to provider failed"
        );
        
        if (fee > 0) {
            require(
                stablecoin.transferFrom(_payer, feeCollector, fee),
                "Fee transfer failed"
            );
            totalFeesCollected[defaultStablecoin] += fee;
        }

        // Record payment
        uint256 paymentId = paymentCounter++;
        payments[paymentId] = Payment({
            paymentId: paymentId,
            payer: _payer,
            recipient: _provider,
            amount: _amount,
            token: defaultStablecoin,
            paymentType: "claim_payout",
            claimId: _claimId,
            timestamp: block.timestamp,
            isCompleted: true,
            transactionHash: "",
            fees: fee
        });

        userPayments[_payer].push(paymentId);
        userPayments[_provider].push(paymentId);

        emit ClaimPayoutExecuted(_claimId, paymentId, _provider, _amount);
        emit PaymentProcessed(paymentId, _payer, _provider, _amount, defaultStablecoin, "claim_payout");
    }

    /**
     * @dev Create an escrow payment
     * @param _recipient Payment recipient
     * @param _amount Payment amount
     * @param _token Stablecoin token address
     * @param _releaseDate When funds can be released
     * @param _condition Condition for release
     * @param _claimId Associated claim ID (0 if not applicable)
     */
    function createEscrow(
        address _recipient,
        uint256 _amount,
        address _token,
        uint256 _releaseDate,
        string memory _condition,
        uint256 _claimId
    ) external nonReentrant whenNotPaused onlyValidStablecoin(_token) {
        require(_recipient != address(0), "Invalid recipient address");
        require(_amount > 0, "Amount must be greater than 0");
        require(_releaseDate > block.timestamp, "Release date must be in future");

        IERC20 stablecoin = IERC20(_token);
        require(
            stablecoin.balanceOf(msg.sender) >= _amount,
            "Insufficient balance"
        );
        require(
            stablecoin.allowance(msg.sender, address(this)) >= _amount,
            "Insufficient allowance"
        );

        // Transfer tokens to escrow
        require(
            stablecoin.transferFrom(msg.sender, address(this), _amount),
            "Escrow transfer failed"
        );

        // Create escrow record
        uint256 escrowId = escrowCounter++;
        escrowPayments[escrowId] = EscrowPayment({
            escrowId: escrowId,
            payer: msg.sender,
            recipient: _recipient,
            amount: _amount,
            token: _token,
            releaseDate: _releaseDate,
            isReleased: false,
            isCancelled: false,
            condition: _condition,
            claimId: _claimId
        });

        emit EscrowCreated(escrowId, msg.sender, _recipient, _amount, _releaseDate);
    }

    /**
     * @dev Release escrow payment
     * @param _escrowId Escrow ID to release
     */
    function releaseEscrow(uint256 _escrowId) 
        external 
        nonReentrant 
        whenNotPaused 
        onlyValidEscrow(_escrowId) 
    {
        EscrowPayment storage escrow = escrowPayments[_escrowId];
        require(
            msg.sender == escrow.payer || 
            msg.sender == escrow.recipient ||
            hasRole(PAYMENT_PROCESSOR_ROLE, msg.sender),
            "Not authorized to release escrow"
        );
        require(!escrow.isReleased, "Escrow already released");
        require(!escrow.isCancelled, "Escrow cancelled");
        require(block.timestamp >= escrow.releaseDate, "Release date not reached");

        // Calculate platform fee
        uint256 fee = (escrow.amount * platformFeePercentage) / 10000;
        uint256 netAmount = escrow.amount - fee;

        IERC20 stablecoin = IERC20(escrow.token);
        
        // Transfer to recipient
        require(
            stablecoin.transfer(escrow.recipient, netAmount),
            "Transfer to recipient failed"
        );
        
        if (fee > 0) {
            require(
                stablecoin.transfer(feeCollector, fee),
                "Fee transfer failed"
            );
            totalFeesCollected[escrow.token] += fee;
        }

        escrow.isReleased = true;

        // Record as payment
        uint256 paymentId = paymentCounter++;
        payments[paymentId] = Payment({
            paymentId: paymentId,
            payer: escrow.payer,
            recipient: escrow.recipient,
            amount: escrow.amount,
            token: escrow.token,
            paymentType: "escrow_release",
            claimId: escrow.claimId,
            timestamp: block.timestamp,
            isCompleted: true,
            transactionHash: "",
            fees: fee
        });

        userPayments[escrow.payer].push(paymentId);
        userPayments[escrow.recipient].push(paymentId);

        emit EscrowReleased(_escrowId, escrow.amount);
        emit PaymentProcessed(
            paymentId, 
            escrow.payer, 
            escrow.recipient, 
            escrow.amount, 
            escrow.token, 
            "escrow_release"
        );
    }

    /**
     * @dev Cancel escrow payment (refund to payer)
     * @param _escrowId Escrow ID to cancel
     */
    function cancelEscrow(uint256 _escrowId) 
        external 
        nonReentrant 
        onlyValidEscrow(_escrowId) 
    {
        EscrowPayment storage escrow = escrowPayments[_escrowId];
        require(
            msg.sender == escrow.payer || hasRole(PAYMENT_PROCESSOR_ROLE, msg.sender),
            "Not authorized to cancel escrow"
        );
        require(!escrow.isReleased, "Escrow already released");
        require(!escrow.isCancelled, "Escrow already cancelled");

        IERC20 stablecoin = IERC20(escrow.token);
        
        // Refund to payer
        require(
            stablecoin.transfer(escrow.payer, escrow.amount),
            "Refund transfer failed"
        );

        escrow.isCancelled = true;

        emit EscrowCancelled(_escrowId);
    }

    /**
     * @dev Get payment details
     * @param _paymentId Payment ID
     */
    function getPayment(uint256 _paymentId) 
        external 
        view 
        onlyValidPayment(_paymentId)
        returns (Payment memory) 
    {
        return payments[_paymentId];
    }

    /**
     * @dev Get user's payments
     * @param _user User address
     */
    function getUserPayments(address _user) 
        external 
        view 
        returns (uint256[] memory) 
    {
        require(
            msg.sender == _user || hasRole(PAYMENT_PROCESSOR_ROLE, msg.sender),
            "Not authorized to view user payments"
        );
        return userPayments[_user];
    }

    /**
     * @dev Get escrow details
     * @param _escrowId Escrow ID
     */
    function getEscrow(uint256 _escrowId) 
        external 
        view 
        onlyValidEscrow(_escrowId)
        returns (EscrowPayment memory) 
    {
        return escrowPayments[_escrowId];
    }

    /**
     * @dev Set platform fee percentage
     * @param _feePercentage New fee percentage (in basis points, e.g., 25 = 0.25%)
     */
    function setPlatformFee(uint256 _feePercentage) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(_feePercentage <= 1000, "Fee cannot exceed 10%"); // Max 10%
        platformFeePercentage = _feePercentage;
    }

    /**
     * @dev Set fee collector address
     * @param _feeCollector New fee collector address
     */
    function setFeeCollector(address _feeCollector) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(_feeCollector != address(0), "Invalid fee collector address");
        feeCollector = _feeCollector;
    }

    /**
     * @dev Withdraw collected fees
     * @param _token Token address
     * @param _amount Amount to withdraw
     */
    function withdrawFees(address _token, uint256 _amount) 
        external 
        onlyRole(TREASURY_ROLE) 
    {
        require(totalFeesCollected[_token] >= _amount, "Insufficient fees collected");
        
        IERC20 stablecoin = IERC20(_token);
        require(
            stablecoin.transfer(feeCollector, _amount),
            "Fee withdrawal failed"
        );
        
        totalFeesCollected[_token] -= _amount;
        emit FeesCollected(_token, _amount);
    }

    /**
     * @dev Emergency pause
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @dev Emergency unpause
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}