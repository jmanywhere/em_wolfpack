//SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IPancakeSwapRouter.sol";

contract WolfpackSwap is Ownable {
    struct Trades {
        uint256 traded;
        bool completed;
    }
    IPancakeSwapRouter public router;

    ERC20 public elephant = ERC20(0xE283D0e3B8c102BAdF5E8166B73E02D96d92F688);
    ERC20 public BUSD = ERC20(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56);

    uint256 public devFee = 25;
    uint256 public marketingFee = 75;
    uint256 public totalTax = 2;

    address public devWallet;
    address public marketingWallet;
    mapping(address => uint256) public traded;

    event Taxes(uint256 dev, uint256 mkt);

    constructor(address _mkt) {
        devWallet = msg.sender;
        marketingWallet = _mkt;
        router = IPancakeSwapRouter(0x10ED43C718714eb63d5aA57B78B54704E256024E);
    }

    /// @notice For these tokens specifically we'll work with everything in BUSD as the interim token
    /// @dev The tax here is in ETH
    function buyWithETH(address output) public payable {
        uint256 amount = msg.value;
        require(amount > 0, "SW:1"); // Invalid amount
        // Take devFee
        uint256 devTax = (amount * totalTax) / 100;
        uint256 mktTax = 0;
        (devTax, mktTax) = spreadTax(devTax);
        if (devTax > 0) {
            (bool succ, ) = payable(devWallet).call{value: devTax}("");
            require(succ, "SW:2"); // Error transfering tax
        }
        if (mktTax > 0) {
            (bool succ, ) = payable(marketingWallet).call{value: mktTax}("");
            require(succ, "SW:2"); // Error transfering tax
        }
        amount = address(this).balance; // get actual ETH amount
        uint8 steps = output == address(BUSD) ? 2 : 3;

        address[] memory path = new address[](steps);
        path[0] = router.WETH();
        path[1] = address(BUSD);
        if (steps == 3) path[2] = output;
        uint256[] memory amounts = router.swapExactETHForTokens{value: amount}(
            1,
            path,
            msg.sender,
            block.timestamp
        );
        increaseTradedValue(amounts[steps - 1], msg.sender, path[steps - 1]);
        emit Taxes(devTax, mktTax);
    }

    function swapTokens(
        address _input,
        address _output,
        uint256 amount
    ) public {
        require(_input != _output && amount > 0, "INPUTS"); // INPUTS MISMATCH

        bool succ = false;
        uint256 devTax = 0;
        uint256 mktTax = 0;
        address[] memory path = new address[](2);

        if (_input == address(BUSD)) {
            // get tax and send it to devs
            succ = BUSD.transferFrom(msg.sender, address(this), amount);
            require(succ, "IN TX"); // failed transfer
            devTax = BUSD.balanceOf(address(this));
            (devTax, mktTax) = spreadTax((devTax * totalTax) / 100);
            if (devTax > 0) {
                succ = BUSD.transfer(devWallet, devTax);
                require(succ, "DTX"); // Failed dev wallet transfer
            }
            if (mktTax > 0) {
                succ = BUSD.transfer(marketingWallet, mktTax);
                require(succ, "MTX"); // Failed marketing wallet transfer
            }
            path[0] = _input;
            path[1] = _output;

            BUSD.approve(address(router), amount);
            uint256[] memory amounts = router.swapExactTokensForTokens(
                BUSD.balanceOf(address(this)),
                1,
                path,
                msg.sender,
                block.timestamp
            );
            increaseTradedValue(amounts[1], msg.sender, _output);
        } else if (_output == address(BUSD)) {
            //swap, then send output to devs
            path[0] = _input;
            path[1] = _output;
            ERC20(_input).approve(address(router), amount);
            router.swapExactTokensForTokens(
                amount,
                1,
                path,
                address(this),
                block.timestamp
            );

            uint256 _total = BUSD.balanceOf(address(this));
            (devTax, mktTax) = spreadTax((_total * totalTax) / 100);
            if (devTax > 0) {
                succ = BUSD.transfer(devWallet, devTax);
                require(succ, "DTX"); // Failed dev wallet transfer
            }
            if (mktTax > 0) {
                succ = BUSD.transfer(marketingWallet, mktTax);
                require(succ, "MTX"); // Failed marketing wallet transfer
            }
            _total = BUSD.balanceOf(address(this));
            BUSD.transfer(msg.sender, _total);
        } else {
            //swap, get BUSD in the middle and do final swap
            path[0] = _input;
            path[1] = address(BUSD);
            ERC20(_input).approve(address(router), amount);
            router.swapExactTokensForTokens(
                amount,
                1,
                path,
                address(this),
                block.timestamp
            );
            uint256 _total = BUSD.balanceOf(address(this));
            (devTax, mktTax) = spreadTax((_total * totalTax) / 100);
            if (devTax > 0) {
                succ = BUSD.transfer(devWallet, devTax);
                require(succ, "DTX"); // Failed dev wallet transfer
            }
            if (mktTax > 0) {
                succ = BUSD.transfer(marketingWallet, mktTax);
                require(succ, "MTX"); // Failed marketing wallet transfer
            }
            emit Taxes(devTax, mktTax);
            _total = BUSD.balanceOf(address(this));
            path[0] = address(BUSD);
            path[1] = _output;
            BUSD.approve(address(router), _total);
            uint256[] memory trades = router.swapExactTokensForTokens(
                _total,
                1,
                path,
                msg.sender,
                block.timestamp
            );
            increaseTradedValue(trades[2], msg.sender, _output);
        }
    }

    function sellForETH(address input, uint256 amount) public {
        require(input != address(elephant), "EMX"); // Unsupported swap using EM as the input token

        bool succ = ERC20(input).transferFrom(
            msg.sender,
            address(this),
            amount
        );
        require(succ, "TKN1"); // Failed to transfer token
        ERC20(input).approve(address(router), amount);

        uint8 steps = input == address(BUSD) ? 2 : 3;
        address[] memory path = new address[](steps);

        path[0] = input;
        if (steps == 2) {
            path[1] = router.WETH();
        } else {
            path[1] = address(BUSD);
            path[2] = router.WETH();
        }

        router.swapExactTokensForETH(
            amount,
            1,
            path,
            address(this),
            block.timestamp
        );
        uint256 total = address(this).balance;
        uint256 devTax = (total * totalTax) / 100;
        uint256 mktTax = 0;
        (devTax, mktTax) = spreadTax(devTax);
        if (devTax > 0) {
            (succ, ) = payable(devWallet).call{value: devTax}("");
            require(succ, "SW:2"); // Error transfering tax
        }
        if (mktTax > 0) {
            (succ, ) = payable(marketingWallet).call{value: mktTax}("");
            require(succ, "SW:2"); // Error transfering tax
        }

        total = address(this).balance;
        (succ, ) = payable(msg.sender).call{value: total}("");
        require(succ, "SELL1"); // Error transfering ETH to user
    }

    function editMktWallet(address _mkt) external onlyOwner {
        require(_mkt != address(0), "MKT"); // Invalid Marketing wallet
        marketingWallet = _mkt;
    }

    function editDevWallet(address _dev) external onlyOwner {
        require(_dev != address(0), "DV"); // Invalid DEV wallet
        devWallet = _dev;
    }

    function increaseTradedValue(
        uint256 _amount,
        address _user,
        address _output
    ) internal {
        if (_output != address(elephant)) return;
        traded[_user] += _amount;
    }

    function editFees(
        uint256 _total,
        uint256 _dev,
        uint256 _mkt
    ) external onlyOwner {
        require(_total <= 15 && _dev + _mkt == 100, "Invalid Params");
        totalTax = _total;
        devFee = _dev;
        marketingFee = _mkt;
    }

    function spreadTax(uint256 _amount)
        internal
        view
        returns (uint256 taxForDev, uint256 taxForMarketing)
    {
        taxForDev = (devFee * _amount) / 100;
        taxForMarketing = _amount - taxForDev;
    }

    function extractTokens(address _token) external onlyOwner {
        ERC20 token = ERC20(_token);
        uint256 total = token.balanceOf(address(this));
        require(total > 0, "No tokens");
        token.transfer(msg.sender, total);
    }
}
