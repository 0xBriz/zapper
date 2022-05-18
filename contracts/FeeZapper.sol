// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./interfaces/IUniswapV2Router.sol";
import "./interfaces/IUniswapV2Pair.sol";

contract FeeZapper is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public zapFee = 1;
    uint256 public constant ZAP_FEE_DENOMINATOR = 100;
    uint256 private constant MAX_ZAP_FEE = 3;

    // Fee receivers
    address public treasuryAddress;
    address public devAddress;

    event ZappedInLP(
        address indexed who,
        address indexed pairAddress,
        uint256 indexed lpAmount
    );

    constructor(address _treasuryAddress, address _devAddress) {
        require(_treasuryAddress != address(0), "!Treasury address");
        require(_devAddress != address(0), "!Dev address");

        treasuryAddress = _treasuryAddress;
        devAddress = _devAddress;
    }

    /// @dev Flexible zap in function. Only assumes basic requirements. Rest is provided externally.
    function zapInWithPath(
        address _tokenInAddress,
        address _pairAddress,
        uint256 _tokenInAmount,
        address _routerAddress,
        address[] calldata _pathTokenInToLp0,
        address[] calldata _pathTokenInToLp1
    ) public nonReentrant {
        require(_tokenInAddress != address(0), "!TokenIn address");
        require(_pairAddress != address(0), "!LP address");
        require(_routerAddress != address(0), "!Router address");
        require(_tokenInAmount > 0, "!tokenInAmount");

        _validateSwapPaths(
            _tokenInAddress,
            _pathTokenInToLp0,
            _pathTokenInToLp1
        );

        address tokenOut0 = _pathTokenInToLp0[_pathTokenInToLp0.length - 1];
        address tokenOut1 = _pathTokenInToLp1[_pathTokenInToLp1.length - 1];

        // Will return the tokens in the correct order for the pair if checks pass.
        // Needed before attempting to add liquidity.
        (address lpToken0, address lpToken1) = _validatePairForRouter(
            _pairAddress,
            _routerAddress,
            tokenOut0,
            tokenOut1
        );

        _pullCallersTokens(_tokenInAddress, _tokenInAmount);
        require(
            IERC20(_tokenInAddress).balanceOf(address(this)) >= _tokenInAmount,
            "Pulled token amount error"
        );

        uint256 tokenAmountAfterFee = _handleFee(
            _tokenInAmount,
            _tokenInAddress
        );

        // Avoid stack too deep
        address tokenIn = _tokenInAddress;
        address pair = _pairAddress;
        address router = _routerAddress;
        address[] calldata path0 = _pathTokenInToLp0;
        address[] calldata path1 = _pathTokenInToLp1;

        uint256 lpAmountIn0;
        uint256 lpAmountIn1;

        if (tokenIn == IUniswapV2Router(router).WETH()) {
            (lpAmountIn0, lpAmountIn1) = _swapETHForLP(
                tokenIn,
                tokenAmountAfterFee,
                router,
                lpToken0,
                lpToken1,
                path0,
                path1
            );
        } else {
            (lpAmountIn0, lpAmountIn1) = _swapForLP(
                tokenIn,
                tokenAmountAfterFee,
                router,
                lpToken0,
                lpToken1,
                path0,
                path1
            );
        }

        // Add liquidity using amount of each token returned from swaps
        uint256 lpTokensReceived = _addLiquidity(
            lpToken0,
            lpToken1,
            router,
            lpAmountIn0,
            lpAmountIn1
        );

        // Return anything left over after process. Contract holds zero funds.
        _returnAssets(path0);
        _returnAssets(path1);

        emit ZappedInLP(msg.sender, pair, lpTokensReceived);
    }

    function _swapForLP(
        address _tokenInAddress,
        uint256 _tokenInAmount,
        address _routerAddress,
        address lpToken0,
        address lpToken1,
        address[] calldata _pathTokenInToLp0,
        address[] calldata _pathTokenInToLp1
    ) private returns (uint256 lpAmountIn0, uint256 lpAmountIn1) {
        // Swap half of input token to get the LP amount to be added for token0
        lpAmountIn0 = _swapInputTokenForLpMember(
            _tokenInAddress,
            _tokenInAmount,
            _routerAddress,
            lpToken0,
            _pathTokenInToLp0
        );

        // Swap half of input token to get the LP amount to be added for token1
        lpAmountIn1 = _swapInputTokenForLpMember(
            _tokenInAddress,
            _tokenInAmount,
            _routerAddress,
            lpToken1,
            _pathTokenInToLp1
        );
    }

    function _swapETHForLP(
        address _tokenInAddress,
        uint256 _tokenInAmount,
        address _routerAddress,
        address lpToken0,
        address lpToken1,
        address[] calldata _pathTokenInToLp0,
        address[] calldata _pathTokenInToLp1
    ) private returns (uint256 lpAmountIn0, uint256 lpAmountIn1) {
        // WETH should be in the path here

        // Swap half of input token to get the LP amount to be added for token0
        lpAmountIn0 = _swapEthForLpMember(
            _tokenInAddress,
            _tokenInAmount,
            _routerAddress,
            lpToken0,
            _pathTokenInToLp0
        );

        // Swap half of input token to get the LP amount to be added for token1
        lpAmountIn1 = _swapEthForLpMember(
            _tokenInAddress,
            _tokenInAmount,
            _routerAddress,
            lpToken1,
            _pathTokenInToLp1
        );
    }

    /// @dev Used to swap input token for each side of the liquidity pair
    function _swapInputTokenForLpMember(
        address _tokenInAddress,
        uint256 _tokenInAmount,
        address _routerAddress,
        address _lpTokenMember,
        address[] calldata _swapPath
    ) private returns (uint256 lpAmountIn) {
        _approveRouterIfNeeded(_tokenInAddress, _routerAddress);

        uint256 halfAmountIn = _tokenInAmount / 2;
        // Only make the swap if input token is not either of the two pair members
        if (_lpTokenMember != _tokenInAddress) {
            uint256[] memory amounts = IUniswapV2Router(_routerAddress)
                .swapExactTokensForTokens(
                    halfAmountIn,
                    0,
                    _swapPath,
                    address(this),
                    block.timestamp
                );

            lpAmountIn = amounts[amounts.length - 1];
        } else {
            // Otherwise just return half as the amount to LP with this token
            lpAmountIn = halfAmountIn;
        }
    }

    function _swapEthForLpMember(
        address _tokenInAddress,
        uint256 _amountETH,
        address _routerAddress,
        address _lpTokenMember,
        address[] calldata _swapPath
    ) private returns (uint256 lpAmountIn) {
        _approveRouterIfNeeded(_tokenInAddress, _routerAddress);

        uint256 halfAmountIn = _amountETH / 2;
        if (_lpTokenMember != _tokenInAddress) {
            uint256[] memory amounts = IUniswapV2Router(_routerAddress)
                .swapExactETHForTokens{value: halfAmountIn}(
                0,
                _swapPath,
                address(this),
                block.timestamp
            );

            lpAmountIn = amounts[amounts.length - 1];
        } else {
            // Otherwise just return half as the amount to LP with this token
            lpAmountIn = halfAmountIn;
        }
    }

    function _addLiquidity(
        address _lpToken0,
        address _lpToken1,
        address _routerAddress,
        uint256 _lpAmountIn0,
        uint256 _lpAmountIn1
    ) private returns (uint256 liquidity) {
        _approveRouterIfNeeded(_lpToken0, _routerAddress);
        _approveRouterIfNeeded(_lpToken1, _routerAddress);

        (, , liquidity) = IUniswapV2Router(_routerAddress).addLiquidity(
            _lpToken0,
            _lpToken1,
            _lpAmountIn0,
            _lpAmountIn1,
            0,
            0,
            msg.sender,
            block.timestamp
        );
    }

    function _handleFee(uint256 _tokenInAmount, address _tokenInAddress)
        private
        returns (uint256 tokenAmountAfterFee)
    {
        uint256 feeAmount = quoteFeeAmount(_tokenInAmount);
        uint256 amountToTreasury = feeAmount / 2;
        uint256 amountToDev = feeAmount - amountToTreasury;
        IERC20(_tokenInAddress).safeTransfer(treasuryAddress, amountToTreasury);
        IERC20(_tokenInAddress).safeTransfer(devAddress, amountToDev);
        tokenAmountAfterFee = _tokenInAmount - feeAmount;
    }

    function quoteFeeAmount(uint256 _tokenInAmount)
        public
        view
        returns (uint256 tokenAmountAfterFee)
    {
        tokenAmountAfterFee = (_tokenInAmount * zapFee) / ZAP_FEE_DENOMINATOR;
    }

    function maxFee() public pure returns (uint256) {
        return MAX_ZAP_FEE;
    }

    /// @dev Need to account for the fact that the input token may be apart of the pair itself.
    /// @dev This mildly complicates the check logic, but is broken out here for readability.
    function _validateSwapPaths(
        address _tokenInAddress,
        address[] calldata _pathTokenInToLp0,
        address[] calldata _pathTokenInToLp1
    ) private pure {
        // Either could be the input token so only a zero check
        require(_pathTokenInToLp0.length > 0, "!_pathTokenInToLp0");
        require(_pathTokenInToLp1.length > 0, "!_pathTokenInToLp1");

        // Both paths should start with the input token
        require(
            _pathTokenInToLp0[0] == _tokenInAddress,
            "_tokenInToLp0[0] != _tokenInAddress"
        );
        require(
            _pathTokenInToLp1[0] == _tokenInAddress,
            "_tokenInToLp1[0] != _tokenInAddress"
        );
    }

    /// @dev Util to validate the pair with the router and put pair tokens in proper order.
    function _validatePairForRouter(
        address _pairAddress,
        address _routerAddress,
        address _lpToken0,
        address _lpToken1
    ) private view returns (address lpToken0, address lpToken1) {
        // validate desired output tokens are actually in the pair to be LP'd in to.
        IUniswapV2Pair pair = IUniswapV2Pair(_pairAddress);

        // validate pair is from the same factory as router to be used
        require(
            pair.factory() == IUniswapV2Router(_routerAddress).factory(),
            "Mismatched factories"
        );

        address pairToken0 = pair.token0();
        address pairToken1 = pair.token1();

        require(
            _lpToken0 == pairToken0 || _lpToken0 == pairToken1,
            "!lpToken0 not in pair"
        );
        require(
            _lpToken1 == pairToken0 || _lpToken1 == pairToken1,
            "!lpToken1 not in pair"
        );

        // Put in right order for adding to pairs liquidity
        lpToken0 = _lpToken0 == pairToken0 ? pairToken0 : pairToken1;
        lpToken1 = _lpToken1 == pairToken1 ? pairToken1 : pairToken0;
    }

    /// @dev Util to run basic checks and then pull in the callers tokens
    function _pullCallersTokens(address _tokenInAddress, uint256 _tokenInAmount)
        internal
    {
        address caller = _msgSender();
        require(_tokenInAmount > 0, "Zero amount");
        require(
            ERC20(_tokenInAddress).allowance(caller, address(this)) >=
                _tokenInAmount,
            "Input token is not approved"
        );
        require(
            ERC20(_tokenInAddress).balanceOf(caller) >= _tokenInAmount,
            "User balance too low"
        );

        // Pull in callers tokens and setup for swap before LP
        IERC20(_tokenInAddress).safeTransferFrom(
            caller,
            address(this),
            _tokenInAmount
        );
    }

    function _approveRouterIfNeeded(
        address _tokenAddress,
        address _routerAddress
    ) private {
        if (
            IERC20(_tokenAddress).allowance(address(this), _routerAddress) == 0
        ) {
            IERC20(_tokenAddress).safeApprove(
                _routerAddress,
                type(uint256).max
            );
        }
    }

    /// @dev Return any dust left over to caller after operations are complete
    function _returnAssets(address[] memory _tokens) private {
        for (uint256 i = 0; i < _tokens.length; i++) {
            IERC20 token = IERC20(_tokens[i]);
            uint256 crumbs = token.balanceOf(address(this));
            if (crumbs > 0) {
                token.safeTransfer(msg.sender, crumbs);
            }
        }
    }

    /* =========================== ADMIN FUNCTIONS ============================= */

    /// @dev return any stuck tokens if needed for some reason
    function adminReturnAssets(
        address _token,
        address _receiver,
        uint256 _amount
    ) external onlyOwner {
        require(_token != address(0), "!Token address");
        require(_receiver != address(0), "!receiver");
        require(_amount > 0, "!Zero amount");

        uint256 balance = IERC20(_token).balanceOf(address(this));
        require(balance >= _amount, "!Insufficient balance");

        IERC20(_token).safeTransfer(_receiver, _amount);
    }

    function updateZapFee(uint256 _fee) external onlyOwner {
        require(_fee <= MAX_ZAP_FEE, "Over max zap fee");

        zapFee = _fee;
    }

    function setFeeReceivers(address _treasuryAddress, address _devAddress)
        external
        onlyOwner
    {
        require(_treasuryAddress != address(0), "!Treasury address");
        require(_devAddress != address(0), "!Dev address");

        treasuryAddress = _treasuryAddress;
        devAddress = _devAddress;
    }
}
