from brownie import accounts, WolfpackSwap, interface
from web3 import Web3 as web3
import pytest


@pytest.fixture
def setup():
    mkt = accounts[1]
    dev = accounts[0]
    swap = WolfpackSwap.deploy(mkt, {"from": dev})
    em = interface.IPancakeERC20("0xE283D0e3B8c102BAdF5E8166B73E02D96d92F688")
    trunk = interface.IPancakeERC20("0xdd325C38b12903B727D16961e61333f4871A70E0")
    busd = interface.IPancakeERC20("0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56")

    return swap, mkt, dev, em, trunk, busd


def test_eth_buy(setup):
    (swap, mkt, dev, em, trunk, busd) = setup
    init_bal = dev.balance()
    init_bal_mkt = mkt.balance()
    swap.buyWithETH(em, {"from": accounts[2], "value": web3.toWei(0.1, "ether")})
    assert dev.balance() - init_bal == web3.toWei(0.0005, "ether")
    assert mkt.balance() - init_bal_mkt == web3.toWei(0.0015, "ether")
    assert em.balanceOf(accounts[2]) > 0

    swap.buyWithETH(trunk, {"from": accounts[2], "value": web3.toWei(1, "ether")})
    swap.buyWithETH(busd, {"from": accounts[2], "value": web3.toWei(1, "ether")})
    assert trunk.balanceOf(accounts[2]) > 0
    assert busd.balanceOf(accounts[2]) > 0


def test_pair_swap(setup):
    (swap, mkt, dev, em, trunk, busd) = setup
    swap.buyWithETH(busd, {"from": accounts[2], "value": web3.toWei(10, "ether")})
    busd.approve(swap, web3.toWei(100, "ether"), {"from": accounts[2]})
    swap.swapTokens(busd, trunk, web3.toWei(100, "ether"), {"from": accounts[2]})

    assert trunk.balanceOf(accounts[2]) > 0
    assert busd.balanceOf(dev) > 0
    assert busd.balanceOf(mkt) > 0
