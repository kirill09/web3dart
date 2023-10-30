part of 'package:web3dart/web3dart.dart';

class SigningInput {
  SigningInput({
    required this.transaction,
    this.chainId,
  });

  final Transaction transaction;
  final int? chainId;
}
