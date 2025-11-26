// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title MoneyPot - Multi-spend Group Saving Pot with m-of-n Approval
/// @notice
/// - Users can create a shared pot, deposit ETH.
/// - A fixed set of approvers (m-of-n) decides each spending request.
/// - Multiple spending requests can be created and executed over time.

contract MoneyPot {
    // ------------------------------------------------------------------------
    //                               DATA STRUCTURES
    // ------------------------------------------------------------------------

    /// @dev Shared pot, like a group wallet / activity fund
    struct Pot {
        uint256 id;
        string name;
        address creator;
        uint256 totalDeposited;   // current ETH balance in this pot (tracked by contract)
        uint256 createdAt;
        bool    isClosed;         // if true, no more deposits or new requests

        // Multi-sig settings
        address[] approvers;      // fixed list of approvers
        uint256   minApprovals;   // m in m-of-n
    }

    /// @dev A single spending proposal from the pot
    struct WithdrawRequest {
        uint256 id;               // index within this pot's requests
        uint256 potId;            // which pot it belongs to
        address proposer;         // who created this request
        address to;               // destination address
        uint256 amount;           // requested amount (in wei)
        string  description;      // e.g. "Tickets", "Bus", "Food"
        uint256 approvalCount;    // how many approvers agreed
        bool    executed;         // whether this request has been executed
    }

    // ------------------------------------------------------------------------
    //                               STATE
    // ------------------------------------------------------------------------

    uint256 public potCount;                          // total pots

    mapping(uint256 => Pot) public pots;              // potId => Pot
    mapping(uint256 => mapping(address => uint256)) public contributions;
    // potId => array of requests
    mapping(uint256 => WithdrawRequest[]) public withdrawRequests;
    // potId => requestId => approver => hasApproved
    mapping(uint256 => mapping(uint256 => mapping(address => bool))) public hasApprovedRequest;

    // ------------------------------------------------------------------------
    //                               EVENTS
    // ------------------------------------------------------------------------

    event PotCreated(
        uint256 indexed potId,
        address indexed creator,
        string  name,
        uint256 approverCount,
        uint256 minApprovals
    );

    event Deposited(
        uint256 indexed potId,
        address indexed from,
        uint256 amount
    );

    event WithdrawRequested(
        uint256 indexed potId,
        uint256 indexed requestId,
        address indexed proposer,
        address to,
        uint256 amount,
        string description
    );

    event WithdrawApproved(
        uint256 indexed potId,
        uint256 indexed requestId,
        address indexed approver,
        uint256 approvalCount
    );

    event WithdrawExecuted(
        uint256 indexed potId,
        uint256 indexed requestId,
        address indexed to,
        uint256 amount
    );

    // ------------------------------------------------------------------------
    //                               MODIFIERS
    // ------------------------------------------------------------------------

    modifier potExists(uint256 potId) {
        require(potId < potCount, "Pot does not exist");
        _;
    }

    modifier potNotClosed(uint256 potId) {
        require(!pots[potId].isClosed, "Pot is closed");
        _;
    }

    // ------------------------------------------------------------------------
    //                               INTERNAL HELPERS
    // ------------------------------------------------------------------------

    /// @dev Check if an address is an approver of this pot
    function _isApprover(Pot storage p, address user)
        internal
        view
        returns (bool)
    {
        for (uint256 i = 0; i < p.approvers.length; i++) {
            if (p.approvers[i] == user) return true;
        }
        return false;
    }

    // ------------------------------------------------------------------------
    //                               CORE LOGIC
    // ------------------------------------------------------------------------

    /// @notice Create a new group pot with fixed approver set and m-of-n rule
    /// @param name        Pot name, e.g. "Hiking Fund"
    /// @param approvers   Addresses who can approve spending
    /// @param minApprovals m in m-of-n (must be <= approvers.length)
    function createPot(
        string calldata name,
        address[] calldata approvers,
        uint256 minApprovals
    ) external returns (uint256 potId) {
        require(approvers.length > 0, "No approvers");
        require(
            minApprovals > 0 && minApprovals <= approvers.length,
            "Invalid minApprovals"
        );

        potId = potCount;

        Pot storage p = pots[potId];
        p.id = potId;
        p.name = name;
        p.creator = msg.sender;
        p.totalDeposited = 0;
        p.createdAt = block.timestamp;
        p.isClosed = false;

        // store approvers
        for (uint256 i = 0; i < approvers.length; i++) {
            require(approvers[i] != address(0), "Zero approver");
            p.approvers.push(approvers[i]);
        }

        p.minApprovals = minApprovals;
        potCount++;

        emit PotCreated(
            potId,
            msg.sender,
            name,
            approvers.length,
            minApprovals
        );
    }

    /// @notice Deposit ETH into a pot
    function deposit(uint256 potId)
        external
        payable
        potExists(potId)
        potNotClosed(potId)
    {
        require(msg.value > 0, "No ETH sent");

        Pot storage p = pots[potId];

        p.totalDeposited += msg.value;
        contributions[potId][msg.sender] += msg.value;

        emit Deposited(potId, msg.sender, msg.value);
    }

    /// @notice Create a spending request from this pot.
    /// @dev 这里可以限制只有 approver 才能提案，或者任何人都能提案。
    ///      简化起见，这里允许任何人提案，但必须 amount <= pot balance。
    function createWithdrawRequest(
        uint256 potId,
        address to,
        uint256 amount,
        string calldata description
    )
        external
        potExists(potId)
        potNotClosed(potId)
        returns (uint256 requestId)
    {
        Pot storage p = pots[potId];

        require(to != address(0), "Invalid to");
        require(amount > 0, "Amount must be > 0");
        require(amount <= p.totalDeposited, "Not enough balance");

        requestId = withdrawRequests[potId].length;

        withdrawRequests[potId].push(
            WithdrawRequest({
                id: requestId,
                potId: potId,
                proposer: msg.sender,
                to: to,
                amount: amount,
                description: description,
                approvalCount: 0,
                executed: false
            })
        );

        emit WithdrawRequested(
            potId,
            requestId,
            msg.sender,
            to,
            amount,
            description
        );
    }

    /// @notice Approver approves a specific withdraw request
    function approveWithdraw(uint256 potId, uint256 requestId)
        external
        potExists(potId)
        potNotClosed(potId)
    {
        Pot storage p = pots[potId];
        require(_isApprover(p, msg.sender), "Not an approver");

        require(requestId < withdrawRequests[potId].length, "Bad requestId");
        WithdrawRequest storage r = withdrawRequests[potId][requestId];

        require(!r.executed, "Already executed");
        require(!hasApprovedRequest[potId][requestId][msg.sender], "Already approved");

        hasApprovedRequest[potId][requestId][msg.sender] = true;
        r.approvalCount += 1;

        emit WithdrawApproved(potId, requestId, msg.sender, r.approvalCount);
    }

    /// @notice Execute a withdraw request after enough approvals (m-of-n)
    /// @dev Anyone can call this; security is enforced by the checks below.
    function executeWithdraw(uint256 potId, uint256 requestId)
        external
        potExists(potId)
        potNotClosed(potId)
    {
        Pot storage p = pots[potId];
        require(requestId < withdrawRequests[potId].length, "Bad requestId");

        WithdrawRequest storage r = withdrawRequests[potId][requestId];

        require(!r.executed, "Already executed");
        require(r.approvalCount >= p.minApprovals, "Not enough approvals");
        require(r.amount <= p.totalDeposited, "Insufficient pot balance");

        // 状态先更新，再转账（防重入）
        r.executed = true;
        p.totalDeposited -= r.amount;

        (bool ok, ) = r.to.call{value: r.amount}("");
        require(ok, "Transfer failed");

        emit WithdrawExecuted(potId, requestId, r.to, r.amount);
    }

    // ------------------------------------------------------------------------
    //                               VIEW FUNCTIONS
    // ------------------------------------------------------------------------

    /// @notice View basic info of a pot
    function getPotInfo(uint256 potId)
        external
        view
        potExists(potId)
        returns (
            string memory name,
            address creator,
            uint256 totalDeposited,
            uint256 createdAt,
            bool isClosed,
            uint256 approverCount,
            uint256 minApprovals
        )
    {
        Pot storage p = pots[potId];
        return (
            p.name,
            p.creator,
            p.totalDeposited,
            p.createdAt,
            p.isClosed,
            p.approvers.length,
            p.minApprovals
        );
    }

    /// @notice Get list of approvers for a pot
    function getApprovers(uint256 potId)
        external
        view
        potExists(potId)
        returns (address[] memory)
    {
        return pots[potId].approvers;
    }

    /// @notice Number of withdraw requests created under this pot
    function getWithdrawRequestCount(uint256 potId)
        external
        view
        potExists(potId)
        returns (uint256)
    {
        return withdrawRequests[potId].length;
    }

    /// @notice Get info of a specific withdraw request
    function getWithdrawRequest(uint256 potId, uint256 requestId)
        external
        view
        potExists(potId)
        returns (
            address proposer,
            address to,
            uint256 amount,
            string memory description,
            uint256 approvalCount,
            bool executed
        )
    {
        require(requestId < withdrawRequests[potId].length, "Bad requestId");

        WithdrawRequest storage r = withdrawRequests[potId][requestId];
        return (
            r.proposer,
            r.to,
            r.amount,
            r.description,
            r.approvalCount,
            r.executed
        );
    }
}
