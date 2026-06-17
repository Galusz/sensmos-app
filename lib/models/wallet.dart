/// AppWallet — para kluczy + adres ETH
/// (nazwa AppWallet bo web3dart eksportuje własny Wallet)
class AppWallet {
  final String address;
  final String privateKeyHex;

  const AppWallet({required this.address, required this.privateKeyHex});

  String get short {
    if (address.length < 10) return address.isEmpty ? '—' : address;
    return '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
  }
}
