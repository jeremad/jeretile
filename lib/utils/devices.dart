import 'dart:convert';

const conf = String.fromEnvironment("JERETILE_DEVICES");
final devices = json.decode(conf);
