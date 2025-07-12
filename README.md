# SimpleSwap

SimpleSwap es un contrato inteligente desarrollado en Solidity para un intercambio descentralizado (DEX) que permite agregar y remover liquidez, realizar swaps de tokens ERC-20, y consultar precios entre pares de tokens. Está desplegado en la red Sepolia en la dirección `0x61c471eee1Dc2cf08ee9620B6c0E89A0aa252E31`.

## Características

- **Agregar Liquidez**: Permite a los usuarios añadir tokens a un par de liquidez, recibiendo tokens de liquidez a cambio.
- **Remover Liquidez**: Permite retirar tokens del par quemando tokens de liquidez.
- **Swap de Tokens**: Facilita el intercambio de tokens ERC-20 (Token A a Token B) con base en las reservas del par.
- **Consulta de Precios**: Calcula el precio de un token en términos de otro según las reservas actuales.
- **Seguridad**: Incluye verificaciones de deadline y cantidades mínimas para transacciones seguras.
- **Tests**: cobertura ≥50%.
- **Front-end**: Interfaz web para interactuar con el contrato (agregar liquidez, swap, consultar precios).
