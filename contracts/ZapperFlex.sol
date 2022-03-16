// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./interfaces/IUniswapV2Router.sol";
import "./interfaces/IUniswapV2Pair.sol";

contract ZapperFlex is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    event ZappedInLP(
        address indexed who,
        address indexed pairAddress,
        uint256 indexed lpAmount
    );

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

        // Swap half of input token to get the LP amount to be added for token0
        uint256 lpAmountIn0 = _swapInputTokenForLpMember(
            _tokenInAddress,
            _tokenInAmount,
            _routerAddress,
            lpToken0,
            _pathTokenInToLp0
        );

        // Swap half of input token to get the LP amount to be added for token1
        uint256 lpAmountIn1 = _swapInputTokenForLpMember(
            _tokenInAddress,
            _tokenInAmount,
            _routerAddress,
            lpToken1,
            _pathTokenInToLp1
        );

        // Add liquidity using amount of each token returned from swaps
        uint256 lpTokensReceived = _addLiquidity(
            lpToken0,
            lpToken1,
            _routerAddress,
            lpAmountIn0,
            lpAmountIn1
        );

        // Return anything left over after process. Contract holds zero funds.
        _returnAssets(_pathTokenInToLp0);
       _returnAssets(_pathTokenInToLp1);

        emit ZappedInLP(msg.sender, _pairAddress, lpTokensReceived);
    }

    /// @dev  Need to account for the fact that the input token may be apart of the pair itself.
    /// This mildly complicates the check logic, but is broken out for readability as best possible.
    function _validateSwapPaths(
        address _tokenInAddress,
        address[] calldata _pathTokenInToLp0,
        address[] calldata _pathTokenInToLp1
    ) private pure {
        // Either could be the input token so a only a zero check
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

    function _pullCallersTokens(address _tokenInAddress, uint256 _tokenInAmount)
        internal
    {
        require(_tokenInAmount > 0, "Zero amount");
        require(
            ERC20(_tokenInAddress).allowance(msg.sender, address(this)) >=
                _tokenInAmount,
            "Input token is not approved"
        );
        require(
            ERC20(_tokenInAddress).balanceOf(msg.sender) >= _tokenInAmount,
            "User balance too low"
        );

        // Pull in callers tokens and setup for swap before LP
        IERC20(_tokenInAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _tokenInAmount
        );
    }

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
}
