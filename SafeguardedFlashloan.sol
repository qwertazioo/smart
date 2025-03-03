contract FlashLoan {
    // Storage for available assets
    mapping(address => uint256) public availableAssets;
    
    // Storage for loan checkpoints
    struct LoanCheckpoint {
        uint256 balance;
        uint256 timestamp;
        uint256 blockNumber;
    }
    
    mapping(address => LoanCheckpoint) private loanHistory;
    mapping(address => uint256) private lastLoanBlock;
    
    // Configuration
    uint256 public constant MIN_LOAN_INTERVAL = 30 minutes;
    uint256 public constant MAX_LOAN_AMOUNT = 1000 ether;
    uint256 public constant MAX_BALANCE_CHANGE = 50;
    
    // Events
    event LoanExecuted(
        address indexed borrower,
        address indexed asset,
        uint256 amount,
        uint256 fee
    );
    
    event LoanFailed(
        address indexed borrower,
        address indexed asset,
        uint256 amount,
        string reason
    );
    
    // Reentrancy protection
    mapping(address => bool) private lockedStatus;
    modifier noReentrancy() {
        require(!lockedStatus[msg.sender], "Reentrancy attack detected");
        lockedStatus[msg.sender] = true;
        _;
        lockedStatus[msg.sender] = false;
    }
    
    // Validate balance changes
    modifier validateBalanceChanges() {
        uint256 currentBalance = availableAssets[msg.sender];
        LoanCheckpoint storage prevCheckpoint = loanHistory[msg.sender];
        
        require(
            block.number > lastLoanBlock[msg.sender],
            "Loan cooldown active"
        );
        
        require(
            block.timestamp >= prevCheckpoint.timestamp + MIN_LOAN_INTERVAL,
            "Must wait minimum interval between loans"
        );
        
        require(
            block.number >= prevCheckpoint.blockNumber + 10,
            "Must advance minimum blocks between loans"
        );
        
        uint256 balanceChangePercentage;
        if (prevCheckpoint.balance == 0) {
            balanceChangePercentage = 0;
        } else {
            balanceChangePercentage = 
                ((currentBalance - prevCheckpoint.balance) * 100) / 
                prevCheckpoint.balance;
        }
        
        require(
            balanceChangePercentage <= MAX_BALANCE_CHANGE,
            "Excessive balance change detected"
        );
        
        loanHistory[msg.sender] = LoanCheckpoint({
            balance: currentBalance,
            timestamp: block.timestamp,
            blockNumber: block.number
        });
        
        lastLoanBlock[msg.sender] = block.number;
        
        _;
    }
    
    // Execute flash loan with safeguards
    function executeFlashLoan(
        address asset,
        uint256 amount,
        address borrower,
        bytes calldata data
    ) external noReentrancy validateBalanceChanges {
        require(amount > 0, "Amount must be greater than 0");
        require(amount <= MAX_LOAN_AMOUNT, "Amount exceeds maximum");
        require(availableAssets[asset] >= amount, "Insufficient liquidity");
        
        uint256 initialBalance = availableAssets[asset];
        uint256 fee = calculateFee(amount);
        
        availableAssets[asset] = 0;
        
        (bool success, ) = borrower.call(data);
        require(success, "Execution failed");
        
        require(
            availableAssets[asset] >= initialBalance + fee,
            "Repayment failed"
        );
        
        emit LoanExecuted(borrower, asset, amount, fee);
    }
    
    // Calculate loan fee
    function calculateFee(uint256 amount) internal pure returns (uint256) {
        return amount * 3 / 1000; // 0.3% fee
    }
    
    // Deposit assets with validation
    function deposit(address asset, uint256 amount) external validateBalanceChanges {
        require(amount > 0, "Amount must be greater than 0");
        availableAssets[asset] += amount;
    }
    
    // Withdraw assets with validation
    function withdraw(address asset, uint256 amount) external validateBalanceChanges {
        require(amount > 0, "Amount must be greater than 0");
        require(availableAssets[asset] >= amount, "Insufficient balance");
        availableAssets[asset] -= amount;
    }
    
    // ETH transfer function using call.value
    function transferETH(address payable recipient, uint256 amount) external noReentrancy {
        require(amount > 0, "Amount must be greater than 0");
        require(amount <= address(this).balance, "Insufficient balance");
        
        (bool success, ) = recipient.call{value: amount}("");
        require(success, "ETH transfer failed");
    }
    
    // View function to check available assets
    function getAvailableAssets(address asset) external view returns (uint256) {
        return availableAssets[asset];
    }
}
