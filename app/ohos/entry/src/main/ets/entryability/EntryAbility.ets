
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import { BootstrapPlugin } from '../platform/BootstrapPlugin';
import { SecureKeyPlugin } from '../platform/SecureKeyPlugin';
import { NativePlayerPlugin } from '../platform/NativePlayerPlugin';
import { DocumentPlugin } from '../platform/DocumentPlugin';
import { ReaderPlugin, WindowPolicy } from '../platform/ReaderPlugin';

export default class EntryAbility extends FlutterAbility {
  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    const plugins = flutterEngine.getPlugins()
    if (!plugins) { throw new Error('Flutter plugin registry unavailable') }
    plugins.add(new BootstrapPlugin())
    plugins.add(new SecureKeyPlugin())
    const documents = new DocumentPlugin(this.context)
    const windowPolicy = new WindowPolicy(this.context)
    plugins.add(documents)
    plugins.add(new ReaderPlugin(this.context, documents, windowPolicy))
    plugins.add(new NativePlayerPlugin(this.context, windowPolicy))
  }
}
