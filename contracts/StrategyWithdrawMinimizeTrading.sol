pragma solidity 0.5.16;
import 'openzeppelin-solidity-2.3.0/contracts/ownership/Ownable.sol';
import 'openzeppelin-solidity-2.3.0/contracts/utils/ReentrancyGuard.sol';
import 'openzeppelin-solidity-2.3.0/contracts/math/SafeMath.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import './uniswap/IUniswapV2Router02.sol';
import './SafeToken.sol';
import './Strategy.sol';

contract StrategyWithdrawMinimizeTrading is Ownable, ReentrancyGuard, Strategy {
    using SafeToken for address;
    using SafeMath for uint256;

    IUniswapV2Factory public factory;
    IUniswapV2Router02 public router;

    /// @dev Create a new withdraw minimize trading strategy instance.
    /// @param _router The Uniswap router smart contract.
    constructor(IUniswapV2Router02 _router) public {
        factory = IUniswapV2Factory(_router.factory());
        router = _router;
    }

    /// @dev Execute worker strategy. Take LP tokens + BaseToken. Return LP tokens + BaseToken.
    /// @param user User address to withdraw liquidity.
    /// @param debt Debt amount in WAD of the user.
    /// @param data Extra calldata information passed along to this strategy.
    function execute(address user, uint256 debt, bytes calldata data) external nonReentrant {
        // 1. Find out what farming token we are dealing with.
        (address baseToken, address fToken, uint256 minFToken) = abi.decode(data, (address, address, uint256));
        IUniswapV2Pair lpToken = IUniswapV2Pair(factory.getPair(fToken, baseToken));
        // 2. Remove all liquidity back to BaseToken and farming tokens.
        lpToken.approve(address(router), uint256(-1));
        router.removeLiquidity(baseToken, fToken, lpToken.balanceOf(address(this)), 0, 0, address(this), now);
        // 3. Convert farming tokens to BaseToken.
        address[] memory path = new address[](2);
        path[0] = fToken;
        path[1] = baseToken;
        fToken.safeApprove(address(router), 0);
        fToken.safeApprove(address(router), uint256(-1));
        uint256 balance = baseToken.myBalance();
        if (debt > balance) {
            // Convert some farming tokens to BaseToken.
            uint256 remainingDebt = debt.sub(balance);
            router.swapTokensForExactTokens(remainingDebt, fToken.myBalance(), path, address(this), now);
        }
        // 4. Return BaseToken back to the original caller.
        uint256 remainingBalance = baseToken.myBalance();
        baseToken.safeTransfer(msg.sender, remainingBalance);
        // 5. Return remaining farming tokens to user.
        uint256 remainingFToken = fToken.myBalance();
        require(remainingFToken >= minFToken, 'insufficient farming tokens received');
        if (remainingFToken > 0) {
            fToken.safeTransfer(user, remainingFToken);
        }
    }

    /// @dev Recover ERC20 tokens that were accidentally sent to this smart contract.
    /// @param token The token contract. Can be anything. This contract should not hold ERC20 tokens.
    /// @param to The address to send the tokens to.
    /// @param value The number of tokens to transfer to `to`.
    function recover(address token, address to, uint256 value) external onlyOwner nonReentrant {
        SafeToken.safeTransfer(token, to, value);
    }

    function() external payable {}
}
