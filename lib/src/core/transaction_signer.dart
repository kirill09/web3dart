part of 'package:web3dart/web3dart.dart';

Future<SigningInput> _fillMissingData({
  required Credentials credentials,
  required Transaction transaction,
  int? chainId,
  bool loadChainIdFromNetwork = false,
  Web3Client? client,
}) async {
  final sender = transaction.from ?? credentials.address;
  final filledData = await _fillMissingDataWithoutCred(
    sender: sender,
    transaction: transaction,
    chainId: chainId,
    loadChainIdFromNetwork: loadChainIdFromNetwork,
    client: client,
  );

  return SigningInput(
    transaction: filledData.transaction,
    chainId: filledData.chainId,
  );
}

class _MissingData {
  _MissingData({
    required this.transaction,
    this.chainId,
  });

  final Transaction transaction;
  final int? chainId;
}

Future<_MissingData> _fillMissingDataWithoutCred({
  required EthereumAddress sender,
  required Transaction transaction,
  int? chainId,
  bool loadChainIdFromNetwork = false,
  Web3Client? client,
}) async {
  if (loadChainIdFromNetwork && chainId != null) {
    throw ArgumentError(
      "You can't specify loadChainIdFromNetwork and specify a custom chain id!",
    );
  }

  var gasPrice = transaction.gasPrice;

  if (client == null &&
      (transaction.nonce == null ||
          transaction.maxGas == null ||
          loadChainIdFromNetwork ||
          (!transaction.isEIP1559 && gasPrice == null))) {
    throw ArgumentError('Client is required to perform network actions');
  }

  if (!transaction.isEIP1559 && gasPrice == null) {
    gasPrice = await client!.getGasPrice();
  }

  var maxFeePerGas = transaction.maxFeePerGas;
  var maxPriorityFeePerGas = transaction.maxPriorityFeePerGas;

  if (transaction.isEIP1559) {
    maxPriorityFeePerGas ??= await _getMaxPriorityFeePerGas();
    maxFeePerGas ??= await _getMaxFeePerGas(
      client!,
      maxPriorityFeePerGas.getInWei,
    );
  }

  final nonce = transaction.nonce ??
      await client!
          .getTransactionCount(sender, atBlock: const BlockNum.pending());

  final maxGas = transaction.maxGas ??
      await client!
          .estimateGas(
            sender: sender,
            to: transaction.to,
            data: transaction.data,
            value: transaction.value,
            gasPrice: gasPrice,
            maxPriorityFeePerGas: maxPriorityFeePerGas,
            maxFeePerGas: maxFeePerGas,
          )
          .then((bigInt) => bigInt.toInt());

  // apply default values to null fields
  final modifiedTransaction = transaction.copyWith(
    value: transaction.value ?? EtherAmount.zero(),
    maxGas: maxGas,
    from: sender,
    data: transaction.data ?? Uint8List(0),
    gasPrice: gasPrice,
    nonce: nonce,
    maxPriorityFeePerGas: maxPriorityFeePerGas,
    maxFeePerGas: maxFeePerGas,
  );

  int resolvedChainId;
  if (!loadChainIdFromNetwork) {
    resolvedChainId = chainId!;
  } else {
    resolvedChainId = await client!.getNetworkId();
  }

  return _MissingData(
    transaction: modifiedTransaction,
    chainId: resolvedChainId,
  );
}

Uint8List prependTransactionType(int type, Uint8List transaction) {
  return Uint8List(transaction.length + 1)
    ..[0] = type
    ..setAll(1, transaction);
}

Uint8List _transactionToBytes(Transaction transaction, int? chainId) {
  if (transaction.isEIP1559 && chainId != null) {
    final encodedTx = LengthTrackingByteSink();
    encodedTx.addByte(0x02);
    encodedTx.add(
      rlp.encode(_encodeEIP1559ToRlp(transaction, null, BigInt.from(chainId))),
    );

    encodedTx.close();
    return encodedTx.asBytes();
  }

  final innerSignature = chainId == null
      ? null
      : MsgSignature(
          BigInt.zero,
          BigInt.zero,
          chainId,
        );

  return uint8ListFromList(
    rlp.encode(_encodeToRlp(transaction, innerSignature)),
  );
}

Uint8List signTransactionRaw(
  Transaction transaction,
  Credentials c, {
  int? chainId = 1,
}) {
  final payload = _transactionToBytes(transaction, chainId);

  final signature = c.signToEcSignature(
    payload,
    chainId: chainId,
    isEIP1559: transaction.isEIP1559 && chainId != null,
  );

  return _transactionAddSign(transaction, signature, chainId: chainId);
}

Uint8List _transactionAddSign(
  Transaction transaction,
  MsgSignature signature, {
  int? chainId,
}) {
  if (transaction.isEIP1559 && chainId != null) {
    return uint8ListFromList(
      rlp.encode(
        _encodeEIP1559ToRlp(transaction, signature, BigInt.from(chainId)),
      ),
    );
  }

  return uint8ListFromList(rlp.encode(_encodeToRlp(transaction, signature)));
}

List<dynamic> _encodeEIP1559ToRlp(
  Transaction transaction,
  MsgSignature? signature,
  BigInt chainId,
) {
  final list = [
    chainId,
    transaction.nonce,
    transaction.maxPriorityFeePerGas!.getInWei,
    transaction.maxFeePerGas!.getInWei,
    transaction.maxGas,
  ];

  if (transaction.to != null) {
    list.add(transaction.to!.addressBytes);
  } else {
    list.add('');
  }

  list
    ..add(transaction.value?.getInWei)
    ..add(transaction.data);

  list.add([]); // access list

  if (signature != null) {
    list
      ..add(signature.v)
      ..add(signature.r)
      ..add(signature.s);
  }

  return list;
}

List<dynamic> _encodeToRlp(Transaction transaction, MsgSignature? signature) {
  final list = [
    transaction.nonce,
    transaction.gasPrice?.getInWei,
    transaction.maxGas,
  ];

  if (transaction.to != null) {
    list.add(transaction.to!.addressBytes);
  } else {
    list.add('');
  }

  list
    ..add(transaction.value?.getInWei)
    ..add(transaction.data);

  if (signature != null) {
    list
      ..add(signature.v)
      ..add(signature.r)
      ..add(signature.s);
  }

  return list;
}

Future<EtherAmount> _getMaxPriorityFeePerGas() {
  // We may want to compute this more accurately in the future,
  // using the formula "check if the base fee is correct".
  // See: https://eips.ethereum.org/EIPS/eip-1559
  return Future.value(EtherAmount.inWei(BigInt.from(1000000000)));
}

// Max Fee = (2 * Base Fee) + Max Priority Fee
Future<EtherAmount> _getMaxFeePerGas(
  Web3Client client,
  BigInt maxPriorityFeePerGas,
) async {
  final blockInformation = await client.getBlockInformation();
  final baseFeePerGas = blockInformation.baseFeePerGas;

  if (baseFeePerGas == null) {
    return EtherAmount.zero();
  }

  return EtherAmount.inWei(
    baseFeePerGas.getInWei * BigInt.from(2) + maxPriorityFeePerGas,
  );
}
