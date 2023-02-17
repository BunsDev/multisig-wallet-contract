// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

enum Status {
    PASSED,
    FAILED,
    PENDING
}

struct TransactionType {
    address to;
    address createdBy;
    uint value;
    bytes data;
    Status status;
}

contract MyCustomMultiSigWallet {
    address[] public owners;
    uint public required;
    uint public nonce; // number of transactions so far
    uint public limitValue; // limit value for transaction
    mapping(address => bool) public isOwner;
    mapping(uint => TransactionType) public transactions;
    mapping(uint => mapping(address => int)) public voted;

    event Deposit(address indexed sender, uint amount, uint balance);
    event SubmitTransaction(
        uint indexed txIndex,
        address indexed creator,
        address indexed to,
        uint value,
        bytes data
    );
    event ConfirmTransaction(address indexed by, uint indexed txIndex);
    event ExecuteTransaction(address indexed owner, uint indexed txIndex);
    event FailedTransaction(address indexed owner, uint indexed txIndex);
    event RevokeConfirmation(address indexed owner, uint indexed txIndex);

    modifier onlyOwner() {
        require(isOwner[msg.sender], "You are not an owner");
        _;
    }

    modifier txExists(uint _txIndex) {
        require(_txIndex < nonce, "Transaction does not exist");
        _;
    }

    modifier notExecuted(uint _txIndex) {
        require(
            transactions[_txIndex].status == Status.PENDING,
            "Transaction already executed"
        );
        _;
    }

    modifier notVoted(uint _txIndex) {
        require(
            voted[_txIndex][msg.sender] == 0,
            "You already voted for this transaction"
        );
        _;
    }

    constructor(address[] memory _owners, uint _required, uint _limitValue) {
        require(_owners.length > 0, "Owners required");
        require(
            _required > 0 && _required <= _owners.length,
            "Required number of owners should be between 1 and total owners"
        );

        for (uint i = 0; i < _owners.length; i++) {
            address owner = _owners[i];
            require(owner != address(0), "Invalid owner");
            require(!isOwner[owner], "Owner not unique");
            isOwner[owner] = true;
        }

        owners = _owners;
        required = _required;
        limitValue = _limitValue;
    }

    // change limit value
    function changeLimitValue(uint _limitValue) public onlyOwner {
        limitValue = _limitValue;
    }

    // submit transaction
    function submitTransaction(
        address _to,
        uint _value,
        bytes memory _data
    ) public onlyOwner returns (uint txIndex) {

        require(_value <= limitValue, "Value is greater than limit value");
        txIndex = nonce++;
        transactions[txIndex] = TransactionType({
            to: _to,
            createdBy: msg.sender,
            value: _value,
            data: _data,
            status: Status.PENDING
        });

        emit SubmitTransaction(txIndex, msg.sender, _to, _value, _data);
    }

    // vote on transaction
    function voteOnTransaction(
        uint _txIndex
    )
        public
        onlyOwner
        txExists(_txIndex)
        notExecuted(_txIndex)
        notVoted(_txIndex)
    {
        voted[_txIndex][msg.sender] = 1;
        emit ConfirmTransaction(msg.sender, _txIndex);
        executeTransaction(_txIndex);
    }

    // unvote on transaction
    function unvoteOnTransaction(
        uint _txIndex
    )
        public
        onlyOwner
        txExists(_txIndex)
        notExecuted(_txIndex)
        notVoted(_txIndex)
    {
        voted[_txIndex][msg.sender] = -1;
        emit ConfirmTransaction(msg.sender, _txIndex);
        executeTransaction(_txIndex);
    }

    // execute a transaction
    function executeTransaction(
        uint _txIndex
    ) public onlyOwner txExists(_txIndex) notExecuted(_txIndex) {
        TransactionType storage transaction = transactions[_txIndex];
        uint count = 0;
        uint downvote;
        for (uint i = 0; i < owners.length; i++) {
            if (voted[_txIndex][owners[i]] == 1) count += 1;
            if (voted[_txIndex][owners[i]] == -1) downvote += 1;

            if (downvote == required) {
                transaction.status = Status.FAILED;
                emit FailedTransaction(msg.sender, _txIndex);
                break;
            }

            if (count == required) {
                transaction.status = Status.PASSED;
                (bool success, ) = transaction.to.call{
                    value: transaction.value
                }(transaction.data);
                if (success) {
                    emit ExecuteTransaction(msg.sender, _txIndex);
                } else {
                    transaction.status = Status.FAILED;
                    emit FailedTransaction(msg.sender, _txIndex);
                }
                break;
            }
        }
    }

    receive() external payable {
        emit Deposit(msg.sender, msg.value, address(this).balance);
    }

    fallback() external payable {
        emit Deposit(msg.sender, msg.value, address(this).balance);
    }
}
