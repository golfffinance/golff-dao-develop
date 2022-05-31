// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import '@openzeppelin/contracts/math/SafeMath.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts/utils/Pausable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/utils/EnumerableSet.sol';
import './lib/ERC20Lib.sol';
import './interfaces/GolffV1ERC20.sol';

contract BridgeChain is Ownable, Pausable {

    using SafeMath for uint256;
    using Address for address;
    using ERC20Lib for IERC20;
    address private constant feeToken = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    EnumerableSet.AddressSet private managers;
    struct BridgeConfig {
        address token;
        uint256 fee;
        uint256 singleMin;
        uint256 singleMax;
        bool enable;
    }
    struct Fee {
        uint256 totalFee;
        uint256 currentFee;
    }
    mapping(address => mapping(uint256 => BridgeConfig)) public configMapping;
    mapping(address => mapping(address => uint256)) public recordMapping;
    mapping(string => bool) backMapping;
    mapping(uint256 => mapping(string => bool)) outMapping;
    mapping(address => Fee) public feeMapping;
    event AddManager(address indexed operator, address manager);
    event SetAdmin(address indexed operator, address oldAdmin, address newAdmin);
    event AddConfig(address indexed operator, address token, uint256 toChain, uint256 fee, uint256 singleMin, uint256 singleMax);
    event UpdateFee(address indexed operator, address token, uint256 toChain, uint256 oldFee, uint256 newFee);
    event UpdateSingle(address indexed operator, address token, uint256 toChain, uint256 singleMin, uint256 singleMax);
    event UpdateEnable(address indexed operator, address token, uint256 toChain, bool enable);
    event BridgeIn(address indexed operator, address indexed receiver, address indexed token, uint256 toChain, uint256 amount, uint256 fee);
    event BridgeBack(address indexed operator, address indexed receiver, address indexed token, uint256 amount, uint256 fee, string fromTxid);
    event BridgeOut(address indexed operator, address indexed receiver, address indexed token, uint256 amount, uint256 fromChain, string fromTxid);
    event Recharge(address indexed operator, address token, uint256 amount);
    event Withdraw(address indexed operator, address indexed receiver, address token, uint256 amount);
    event WithdrawFee(address indexed operator, address indexed receiver, address token, uint256 fee);
    event WithdrawAllFee(address indexed operator, address indexed receiver, address[] token, uint256 fee);
    modifier onlyManager() {
        require(isManager(msg.sender), "BridgeChain: caller is not the manager");
        _;
    }
    modifier checkBridgeIn(address _receiver, address _token, uint256 _toChain, uint256 _amount) {
        require(_receiver != address(0), 'BridgeChain: receiver is the zero address');
        require(_token != address(0), 'BridgeChain: token is the zero address');
        require(_amount > 0, 'BridgeChain: quantity cannot be zero');
        BridgeConfig memory bridgeConfig = configMapping[_token][_toChain];
        require(bridgeConfig.token != address(0), 'BridgeChain: token config does not exist');
        require(bridgeConfig.enable, 'BridgeChain: token config not enabled');
        require(_amount >= bridgeConfig.singleMin, 'BridgeChain: less than single minimum quantity');
        require(_amount <= bridgeConfig.singleMax, 'BridgeChain: greater than the maximum quantity');
        _;
    }

    constructor () public {
        emit AddManager(msg.sender, msg.sender);
        EnumerableSet.add(managers, msg.sender);
        //addManager(msg.sender);
    }

    function bridgeIn(address _receiver, address _token, uint256 _toChain, uint256 _amount) external payable whenNotPaused checkBridgeIn(_receiver, _token, _toChain, _amount) {
        BridgeConfig memory bridgeConfig = configMapping[_token][_toChain];
        IERC20(feeToken).universalTransferFrom(msg.sender, address(this), bridgeConfig.fee);
        GolffV1ERC20(_token).burnFrom(msg.sender, _amount);
        Fee storage fee = feeMapping[_token];
        fee.totalFee = fee.totalFee.add(bridgeConfig.fee);
        fee.currentFee = fee.currentFee.add(bridgeConfig.fee);
        uint256 record = recordMapping[msg.sender][_token];
        recordMapping[msg.sender][_token] = record.add(_amount);
        emit BridgeIn(msg.sender, _receiver, _token, _toChain, _amount, bridgeConfig.fee);
    }
    function bridgeBack(address _receiver, address _token, uint256 _amount, uint256 _fee, string calldata _fromTxid) external onlyManager {
        require(!backMapping[_fromTxid], 'BridgeChain:: txid returned');
        uint256 feeBalance = IERC20(feeToken).universalBalanceOf(address(this));
        require(feeBalance >= _fee, 'BridgeChain: greater than current balance');
        IERC20(feeToken).universalTransfer(_receiver, _fee);
        GolffV1ERC20(_token).mint(_receiver, _amount);

        Fee storage fee = feeMapping[_token];
        fee.totalFee = fee.totalFee.sub(_fee);
        fee.currentFee = fee.currentFee.sub(_fee);
        uint256 record = recordMapping[_receiver][_token];
        require(record >= _amount, 'BridgeChain: greater than current record');
        recordMapping[_receiver][_token] = record.sub(_amount);
        backMapping[_fromTxid] = true;
        emit BridgeBack(msg.sender, _receiver, _token, _amount, _fee, _fromTxid);
    }
    function bridgeOut(address _receiver, address _token, uint256 _amount, uint256 _fromChain, string memory _fromTxid) external onlyManager {
        require(!outMapping[_fromChain][_fromTxid], 'BridgeChain: txid posted');
        outMapping[_fromChain][_fromTxid] = true;
        GolffV1ERC20(_token).mint(_receiver, _amount);
        emit BridgeOut(msg.sender, _receiver, _token, _amount, _fromChain, _fromTxid);
    }

    function withdrawFee(address _receiver, address _token, uint256 _fee) external onlyManager {
        require(_receiver != address(0), "BridgeChain: manager is the zero address");
        uint256 balance = IERC20(feeToken).universalBalanceOf(address(this));
        require(balance >= _fee, 'BridgeChain: greater than current balance');
        IERC20(feeToken).universalTransfer(_receiver, _fee);
        Fee storage fee = feeMapping[_token];
        fee.currentFee = fee.currentFee.sub(_fee);
        emit WithdrawFee(msg.sender, _receiver, _token, _fee);
    }
    function withdrawAllFee(address _receiver, address[] calldata _token) external onlyManager {
        require(_receiver != address(0), "BridgeChain: manager is the zero address");
        require(_token.length > 0, "BridgeChain: token length is the zero");
        uint256 totalFee = 0;
        for (uint i = 0; i < _token.length; i++) {
            Fee storage fee = feeMapping[_token[i]];
            totalFee = totalFee.add(fee.currentFee);
            fee.currentFee = 0;
        }
        uint256 balance = IERC20(feeToken).universalBalanceOf(address(this));
        require(balance >= totalFee, 'BridgeChain: greater than current balance');
        IERC20(feeToken).universalTransfer(_receiver, totalFee);
        emit WithdrawAllFee(msg.sender, _receiver, _token, totalFee);
    }
    function addManager(address _manager) external onlyOwner returns (bool) {
        require(_manager != address(0), "BridgeChain: manager is the zero address");
        emit AddManager(msg.sender, _manager);
        return EnumerableSet.add(managers, _manager);
    }
    function delManager(address _manager) external onlyOwner returns (bool) {
        require(_manager != address(0), "BridgeChain: manager is the zero address");
        return EnumerableSet.remove(managers, _manager);
    }
    function getManagerLength() public view returns (uint256) {
        return EnumerableSet.length(managers);
    }
    function getManager(uint256 _index) external view returns (address){
        require(_index <= getManagerLength() - 1, "BridgeChain: index out of bounds");
        return EnumerableSet.at(managers, _index);
    }
    function isManager(address _manager) public view returns (bool) {
        return EnumerableSet.contains(managers, _manager);
    }
    function addConfig(address _token, uint256 _toChain, uint256 _fee, uint256 _singleMin, uint256 _singleMax) external onlyManager returns (bool) {
        require(_token != address(0), "BridgeChain: token is the zero address");
        require(_singleMax > _singleMin, 'BridgeChain: singleMax must be greater than singleMin');
        BridgeConfig memory bridgeConfig = configMapping[_token][_toChain];
        require(bridgeConfig.token == address(0), 'BridgeChain: token already exists');
        configMapping[_token][_toChain] = BridgeConfig({
        token : _token,
        fee : _fee,
        singleMin : _singleMin,
        singleMax : _singleMax,
        enable : true
        });
        emit AddConfig(msg.sender, _token, _toChain, _fee, _singleMin, _singleMax);
        return true;
    }
    function updateFee(address _token, uint256 _toChain, uint256 _fee) external onlyManager returns (bool) {
        BridgeConfig storage bridgeConfig = configMapping[_token][_toChain];
        require(bridgeConfig.token != address(0), 'BridgeChain: token does not exist');
        emit UpdateFee(msg.sender, _token, _toChain, bridgeConfig.fee, _fee);
        bridgeConfig.fee = _fee;
        return true;
    }
    function updateSingle(address _token, uint256 _toChain, uint256 _singleMin, uint256 _singleMax) external onlyManager returns (bool) {
        require(_singleMax > _singleMin, 'BridgeChain: singleMax must be greater than singleMin');
        BridgeConfig storage bridgeConfig = configMapping[_token][_toChain];
        require(bridgeConfig.token != address(0), 'BridgeChain: token does not exist');
        bridgeConfig.singleMin = _singleMin;
        bridgeConfig.singleMax = _singleMax;
        emit UpdateSingle(msg.sender, _token, _toChain, _singleMin, _singleMax);
        return true;
    }
    function updateEnable(address _token, uint256 _toChain, bool _enable) external onlyManager returns (bool) {
        BridgeConfig storage bridgeConfig = configMapping[_token][_toChain];
        require(bridgeConfig.token != address(0), 'BridgeChain: token does not exist');
        require(bridgeConfig.enable != _enable, "BridgeChain: no change required");
        bridgeConfig.enable = _enable;
        emit UpdateEnable(msg.sender, _token, _toChain, _enable);
        return true;
    }
    function pause() external onlyManager returns (bool) {
        _pause();
        return true;
    }

    function unpause() external onlyManager returns (bool) {
        _unpause();
        return true;
    }

}
