// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "./interfaces/IUniswapV2Router.sol";
import "./interfaces/IUniswapV2Pair.sol";

contract ZapperUpgradeable is OwnableUpgradeable {
    using SafeERC20Upgradeable for ERC20Upgradeable;

    event ZappedInLP(
        address indexed who,
        address indexed pairAddress,
        uint256 indexed lpAmount
    );

    function initialize() public initializer {
        __Ownable_init();
    }

    function zapInWithPath(
        address _tokenInAddress,
        address _pairAddress,
        uint256 _tokenInAmount,
        address _routerAddress,
        address[] calldata _path
    ) public {
        require(_tokenInAddress != address(0), "TokenIn address");
        require(_pairAddress != address(0), "LP address");
        require(_routerAddress != address(0), "Router address");
        require(_tokenInAmount > 0, "!tokenInAmount");
        require(_path.length >= 2, "!path");

        IUniswapV2Pair pair = _validatePairForRouter(
            _pairAddress,
            _tokenInAddress,
            _routerAddress
        );

        (address tokenIn, address tokenOut) = _getTokenInTokenOut(
            _tokenInAddress,
            pair
        );

        uint256 liquidity = _swapAndAddLiquidity(
            _pairAddress,
            _tokenInAmount,
            _routerAddress,
            _path,
            tokenIn,
            tokenOut
        );

        _returnAssets(_path);

        emit ZappedInLP(msg.sender, _pairAddress, liquidity);
    }

    /// @dev Set routing path accordingly for the pair, given the desired input token
    function _getTokenInTokenOut(address _tokenInAddress, IUniswapV2Pair pair)
        private
        view
        returns (address tokenIn, address tokenOut)
    {
        bool isInputA = pair.token0() == _tokenInAddress;
        if (isInputA) {
            tokenIn = pair.token0();
            tokenOut = pair.token1();
        } else {
            tokenIn = pair.token1();
            tokenOut = pair.token0();
        }
    }

    function _pullCallersTokens(address _tokenInAddress, uint256 _tokenInAmount)
        private
    {
        require(_tokenInAmount > 0, "Zero amount");
        require(
            ERC20Upgradeable(_tokenInAddress).allowance(
                msg.sender,
                address(this)
            ) >= _tokenInAmount,
            "Input token is not approved"
        );
        require(
            ERC20Upgradeable(_tokenInAddress).balanceOf(msg.sender) >=
                _tokenInAmount,
            "User balance too low"
        );

        // Pull in callers tokens and setup for swap before LP
        ERC20Upgradeable(_tokenInAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _tokenInAmount
        );
    }

    function _swapAndAddLiquidity(
        address _pairAddress,
        uint256 _tokenInAmount,
        address _routerAddress,
        address[] calldata _path,
        address tokenIn,
        address otherToken
    ) private returns (uint256 liquidity) {
        uint256[] memory amounts = _swap(
            _tokenInAmount,
            tokenIn,
            _routerAddress,
            _path
        );

        uint256 tokenInLpAmount = amounts[0];
        uint256 otherTokenLpAmount = amounts[amounts.length - 1];
        liquidity = _addLiquidity(
            tokenIn,
            otherToken,
            _pairAddress,
            _routerAddress,
            tokenInLpAmount,
            otherTokenLpAmount
        );
    }

    /// @dev sells half of `_tokenInAmount` for the output token of `path`.
    function _swap(
        uint256 _tokenInAmount,
        address _tokenIn,
        address _routerAddress,
        address[] memory _path
    ) private returns (uint256[] memory) {
        uint256 sellAmount = _tokenInAmount / 2;
        _approveRouter(_tokenIn, _routerAddress);
        return
            IUniswapV2Router(_routerAddress).swapExactTokensForTokens(
                sellAmount,
                0,
                _path,
                address(this),
                block.timestamp
            );
    }

    function _addLiquidity(
        address _tokenIn,
        address _otherToken,
        address _pairAddress,
        address _routerAddress,
        uint256 _tokenInLpAmount,
        uint256 _otherTokenLpAmount
    ) private returns (uint256 liquidity) {
        _approveRouter(_otherToken, _routerAddress);
        _approveRouter(_pairAddress, _routerAddress);
        (, , liquidity) = IUniswapV2Router(_routerAddress).addLiquidity(
            _tokenIn,
            _otherToken,
            _tokenInLpAmount,
            _otherTokenLpAmount,
            0,
            0,
            msg.sender,
            block.timestamp
        );
    }

    function _validatePairForRouter(
        address _pairAddress,
        address _validateTokenAddress,
        address _routerAddress
    ) private view returns (IUniswapV2Pair pair) {
        // Validate input token and LP pair against router
        pair = IUniswapV2Pair(_pairAddress);
        require(
            pair.factory() == IUniswapV2Router(_routerAddress).factory(),
            "Incompatible liquidity pair factory"
        );
        require(
            pair.token0() == _validateTokenAddress ||
                pair.token1() == _validateTokenAddress,
            "Input token not present in liquidity pair"
        );
    }

    function _approveRouter(address _tokenAddress, address _routerAddress)
        private
    {
        if (
            ERC20Upgradeable(_tokenAddress).allowance(
                address(this),
                _routerAddress
            ) == 0
        ) {
            ERC20Upgradeable(_tokenAddress).safeApprove(
                _routerAddress,
                type(uint256).max
            );
        }
    }

    /// @dev Return any dust left over to caller after operations are complete
    function _returnAssets(address[] memory _tokens) private {
        for (uint256 i = 0; i < _tokens.length; i++) {
            ERC20Upgradeable token = ERC20Upgradeable(_tokens[i]);
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
    ) public onlyOwner {
        require(_token != address(0), "Token address");
        require(_amount > 0, "Zero amount");
        uint256 balance = ERC20Upgradeable(_token).balanceOf(address(this));
        require(balance >= _amount, "Zero amount");
        ERC20Upgradeable(_token).safeTransfer(_receiver, _amount);
    }
}
