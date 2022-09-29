//SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IPancakeSwapRouter.sol";

contract WolfpackSwap {
    IPancakeSwapRouter public router;

    ERC20 public elephant;
    ERC20 public trunk;

    uint256 public devFee = 25;
    uint256 public marketingFee = 75;
    uint256 public totalTax = 2;

    address public devWallet;
    address public marketingWallet;

    constructor(address _mkt) {
        devWallet = msg.sender;
        marketingWallet = _mkt;
    }

    function buyEMwithETH() public payable {
        uint256 amount = msg.value;
        require(amount > 0, "SW:1"); // Invalid amount

        // Take devFee
        uint256 devTax = (amount * totalTax) / 100;
        uint256 marketing = 0;
        (devTax, marketing) = spreadTax(devTax);
        if (devTax > 0) {
            (bool succ, ) = payable(devWallet).call{value: devTax}("");
            require(succ, "SW:2"); // Error transfering tax
        }
        if (marketing > 0) {
            (bool succ, ) = payable(marketingWallet).call{value: marketing}("");
            require(succ, "SW:2"); // Error transfering tax
        }

        amount = address(this).balance; // get actual ETH amount
    }

    function buyEMwithToken() public {}

    function sellEMforETH() public payable {}

    function sellEMforToken() public payable {}

    function quoteETH() public view returns (uint256) {}

    function quoteToken() public view returns (uint256) {}

    function spreadTax(uint256 _amount)
        internal
        view
        returns (uint256 taxForDev, uint256 taxForMarketing)
    {
        taxForDev = (devFee * _amount) / 100;
        taxForMarketing = _amount - taxForDev;
    }
}
