import 'package:hooks/hooks.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';

/// Compiles the Rust crate in `rust/` for whichever platform Flutter is building and bundles it
/// as the native asset behind `lib/src/bindings.dart`.
void main(List<String> args) async {
  await build(args, (input, output) async {
    await const RustBuilder(assetName: 'src/bindings.dart').run(input: input, output: output);
  });
}
