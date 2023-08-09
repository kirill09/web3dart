import 'package:web3dart/web3dart.dart';

class TransactionMissingData {
  TransactionMissingData(this.transaction, this.chainId);

  final Transaction transaction;
  final int? chainId;
}
