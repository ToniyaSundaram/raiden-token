pragma solidity ^0.4.11;

import './ERC223ReceivingContract.sol';

/// @title Base Token contract - Functions to be implemented by token contracts.
contract Token {
    /*
        Implements ERC 20 standard.
        Added support for the ERC 223 "tokenFallback" function and "transfer" function with a payload.
        https://github.com/ethereum/EIPs/issues/20
        https://github.com/ethereum/EIPs/issues/223
     */

    /*
        This is a slight change to the ERC20 base standard.
        function totalSupply() constant returns (uint256 supply);
        is replaced with:
        uint256 public totalSupply;
        This automatically creates a getter function for the totalSupply.
        This is moved to the base contract since public getter functions are not
        currently recognised as an implementation of the matching abstract
        function by the compiler.
    */
    uint256 public totalSupply;

    /*
     *  ERC 20
     */
    function balanceOf(address _owner) constant returns (uint256 balance);
    function transfer(address _to, uint256 _value) returns (bool success);
    function transferFrom(address _from, address _to, uint256 _value) returns (bool success);
    function approve(address _spender, uint256 _value) returns (bool success);
    function allowance(address _owner, address _spender) constant returns (uint256 remaining);

    /*
     *  ERC 223
     */
    function transfer(address _to, uint256 _value, bytes _data) returns (bool success);

    /*
     *  Events
     */
    event Transfer(
        address indexed _from,
        address indexed _to,
        uint256 _value,
        bytes indexed _data);
    event Approval(
        address indexed _owner,
        address indexed _spender,
        uint256 _value);
}


/// @title Standard token contract - Standard token implementation.
contract StandardToken is Token {

    /*
     *  Data structures
     */
    mapping (address => uint256) balances;
    mapping (address => mapping (address => uint256)) allowed;

    /*
     *  Public functions
     */
    /// @dev Transfers sender's tokens to a given address. Returns success.
    /// @param _to Address of token receiver.
    /// @param _value Number of tokens to transfer.
    /// @return Returns success of function call.
    function transfer(address _to, uint256 _value)
        public
        returns (bool)
    {
        bytes memory empty;
        return transfer(_to, _value, empty);
    }

    /// @dev Function that is called when a user or another contract wants to transfer funds.
    /// @param _to Address of token receiver.
    /// @param _value Number of tokens to transfer.
    /// @param _data Data to be sent to tokenFallback
    /// @return Returns success of function call.
    function transfer(
        address _to,
        uint256 _value,
        bytes _data)
        public
        returns (bool)
    {
        require(_to != 0x0);
        require(_value > 0);
        require(balances[msg.sender] >= _value);
        require(balances[_to] + _value > balances[_to]);

        uint codeLength;

        assembly {
            // Retrieve the size of the code on target address, this needs assembly .
            codeLength := extcodesize(_to)
        }

        balances[msg.sender] -= _value;
        balances[_to] += _value;

        if(codeLength > 0) {
            ERC223ReceivingContract receiver = ERC223ReceivingContract(_to);
            receiver.tokenFallback(msg.sender, _value, _data);
        }
        Transfer(msg.sender, _to, _value, _data);
        return true;
    }

    /// @dev Allows allowed third party to transfer tokens from one address to another. Returns success.
    /// @param _from Address from where tokens are withdrawn.
    /// @param _to Address to where tokens are sent.
    /// @param _value Number of tokens to transfer.
    /// @return Returns success of function call.
    function transferFrom(address _from, address _to, uint256 _value)
        public
        returns (bool)
    {
        require(_from != 0x0);
        require(_to != 0x0);
        require(_value > 0);
        require(balances[_from] >= _value);
        require(allowed[_from][_to] >= _value);
        require(balances[_to] + _value > balances[_to]);

        balances[_to] += _value;
        balances[_from] -= _value;
        allowed[_from][_to] -= _value;

        bytes memory empty;
        Transfer(_from, _to, _value, empty);
        return true;
    }

    /// @dev Sets approved amount of tokens for spender. Returns success.
    /// @param _spender Address of allowed account.
    /// @param _value Number of approved tokens.
    /// @return Returns success of function call.
    function approve(address _spender, uint256 _value)
        public
        returns (bool)
    {
        require(_spender != 0x0);
        require(_value > 0);

        allowed[msg.sender][_spender] = _value;
        Approval(msg.sender, _spender, _value);
        return true;
    }

    /*
     * Read functions
     */
    /// @dev Returns number of allowed tokens for given address.
    /// @param _owner Address of token owner.
    /// @param _spender Address of token spender.
    /// @return Returns remaining allowance for spender.
    function allowance(address _owner, address _spender)
        constant
        public
        returns (uint256)
    {
        return allowed[_owner][_spender];
    }

    /// @dev Returns number of tokens owned by given address.
    /// @param _owner Address of token owner.
    /// @return Returns balance of owner.
    function balanceOf(address _owner)
        constant
        public
        returns (uint256)
    {
        return balances[_owner];
    }
}


/// @title Gnosis token contract
/// @author [..] credits to Stefan George - <stefan.george@consensys.net>
contract CustomToken is StandardToken {

    /*
     *  Token meta data
     */
    string constant public name = "The Token";
    string constant public symbol = "TKN";
    uint8 constant public decimals = 18;
    uint constant multiplier = 10**uint(decimals);

    address public owner;
    address public auction_address;

    event Deployed(
        address indexed _auction,
        uint indexed _total_supply,
        uint indexed _auction_supply);
    event Burnt(
        address indexed _receiver,
        uint indexed _num,
        uint indexed _total_supply);
    event ReceivedFunds(uint indexed _num);

    /*
     *  Public functions
     */
    /// @dev Contract constructor function sets dutch auction contract address and assigns all tokens to dutch auction.
    /// @param auction Address of dutch auction contract.
    /// @param initial_supply Number of initially provided tokens.
    /// @param owners Array of addresses receiving preassigned tokens.
    /// @param tokens Array of preassigned token amounts.
    function CustomToken(
        address auction,
        uint initial_supply,
        address[] owners,
        uint[] tokens)
        public
    {
        // Auction address should not be null.
        require(auction != 0x0);
        require(owners.length == tokens.length);
        // Initial supply is in Tei
        require(initial_supply > multiplier);

        owner = msg.sender;
        auction_address = auction;

        // total supply of Tei at deployment
        totalSupply = initial_supply;

        bytes memory empty;

        // Preallocate tokens to beneficiaries
        uint prealloc_tokens;
        for (uint i=0; i<owners.length; i++) {
            // Address should not be null.
            require(owners[i] != 0x0);
            require(tokens[i] > 0);
            require(balances[owners[i]] + tokens[i] > balances[owners[i]]);
            require(prealloc_tokens + tokens[i] > prealloc_tokens);

            balances[owners[i]] += tokens[i];
            prealloc_tokens += tokens[i];
            Transfer(0, owners[i], tokens[i], empty);
        }

        balances[auction_address] = totalSupply - prealloc_tokens;
        Transfer(0, auction_address, balances[auction], empty);

        Deployed(auction_address, totalSupply, balances[auction]);

        assert(totalSupply == balances[auction_address] + prealloc_tokens);
    }

    /// @dev Transfers auction funds; called from auction after it has ended.
    function receiveFunds()
        public
        payable
    {
        require(msg.sender == auction_address);
        require(msg.value > 0);

        ReceivedFunds(msg.value);
        assert(this.balance > 0);
    }

    /// @dev Allows to destroy tokens without receiving the corresponding amount of ether
    /// @param num Number of tokens to burn
    function burn(uint num)
        public
    {
        require(num > 0);
        require(balances[msg.sender] >= num);
        require(totalSupply >= num);

        uint pre_balance = balances[msg.sender];

        balances[msg.sender] -= num;
        totalSupply -= num;
        Burnt(msg.sender, num, totalSupply);

        assert(balances[msg.sender] == pre_balance - num);
    }

}
