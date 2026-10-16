
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import { BootstrapPlugin } from '../platform/BootstrapPlugin';

export default class EntryAbility extends FlutterAbility {
  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    const plugins = flutterEngine.getPlugins()
    if (!plugins) { throw new Error('Flutter plugin registry unavailable') }
    plugins.add(new BootstrapPlugin())
  }
}
