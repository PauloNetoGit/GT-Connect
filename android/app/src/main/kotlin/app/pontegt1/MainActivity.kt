package app.pontegt1

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.media.midi.MidiDevice
import android.media.midi.MidiDeviceInfo
import android.media.midi.MidiManager
import android.media.midi.MidiOutputPort
import android.media.midi.MidiReceiver
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Ponte entre o pedal (Bluetooth MIDI ou USB MIDI padrão) e a BOSS GT-1 (USB).
 *
 * A porta USB da GT-1 não é "class compliant", então o Android não a mostra como dispositivo MIDI.
 * Aqui a interface MIDI dela é aberta direto pelo USB Host, trocando pacotes USB-MIDI de 4 bytes.
 * O pedal entra pelo MidiManager do Android (Bluetooth LE MIDI ou USB MIDI padrão).
 */
@SuppressLint("MissingPermission")
class MainActivity : FlutterActivity() {

    companion object {
        private const val ACTION_USB_PERMISSION = "app.pontegt1.USB_PERMISSION"
        private const val ROLAND_VENDOR_ID = 0x0582
        private val MIDI_SERVICE_UUID: ParcelUuid =
            ParcelUuid.fromString("03B80E5A-EDE8-4B33-A751-6CE34EC4C700")
        private val PEDAL_NAME = Regex("chocolate|m-?vave|footctrl|cuvave|midi", RegexOption.IGNORE_CASE)
    }

    private val main = Handler(Looper.getMainLooper())
    private var events: EventChannel.EventSink? = null

    // ---- GT-1 (USB host) ----
    private lateinit var usb: UsbManager
    private var conn: UsbDeviceConnection? = null
    private var usbIface: UsbInterface? = null
    private var epIn: UsbEndpoint? = null
    private var epOut: UsbEndpoint? = null
    private var openedName: String? = null
    private var reader: Thread? = null
    @Volatile private var reading = false
    private var pendingOpen: MethodChannel.Result? = null
    private var pendingDevice: UsbDevice? = null
    private val sender: ExecutorService = Executors.newSingleThreadExecutor()

    // ---- Pedal (MidiManager) ----
    private var midiManager: MidiManager? = null
    private var pedalDevice: MidiDevice? = null
    private var pedalPort: MidiOutputPort? = null
    private var scanner: BluetoothLeScanner? = null
    private var scanning = false
    private val seenBle = HashMap<String, BluetoothDevice>()

    // ------------------------------------------------------------------ setup
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        usb = getSystemService(Context.USB_SERVICE) as UsbManager
        if (packageManager.hasSystemFeature(PackageManager.FEATURE_MIDI)) {
            midiManager = getSystemService(Context.MIDI_SERVICE) as MidiManager
            @Suppress("DEPRECATION")
            midiManager?.registerDeviceCallback(midiCallback, main)
        }

        val filter = IntentFilter().apply {
            addAction(ACTION_USB_PERMISSION)
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
            addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
        }
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(receiver, filter)
        }

        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "pontegt1/native").setMethodCallHandler { call, result ->
            try {
                handle(call, result)
            } catch (e: Exception) {
                result.error("erro", e.message ?: e.toString(), null)
            }
        }
        EventChannel(messenger, "pontegt1/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) { events = sink }
            override fun onCancel(arguments: Any?) { events = null }
        })
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action == UsbManager.ACTION_USB_DEVICE_ATTACHED) emit(mapOf("type" to "usbAttached"))
    }

    override fun onDestroy() {
        bleScanStop()
        closePedal()
        closeUsb()
        try { unregisterReceiver(receiver) } catch (_: Exception) {}
        @Suppress("DEPRECATION")
        midiManager?.unregisterDeviceCallback(midiCallback)
        sender.shutdownNow()
        super.onDestroy()
    }

    private fun emit(map: Map<String, Any?>) {
        main.post { events?.success(map) }
    }

    private fun status(what: String, state: String, message: String? = null) {
        emit(mapOf("type" to "status", "what" to what, "state" to state, "message" to message))
    }

    // ------------------------------------------------------------------ canal de métodos
    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "sdkInt" -> result.success(Build.VERSION.SDK_INT)
            "keepScreenOn" -> {
                if (call.argument<Boolean>("on") == true) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                result.success(null)
            }
            "usbList" -> result.success(usb.deviceList.values.map { d ->
                mapOf(
                    "deviceName" to d.deviceName,
                    "name" to (d.productName ?: "USB ${hex4(d.vendorId)}:${hex4(d.productId)}"),
                    "vendorId" to d.vendorId,
                    "productId" to d.productId,
                    "roland" to (d.vendorId == ROLAND_VENDOR_ID),
                    "hasPermission" to usb.hasPermission(d),
                )
            })
            "usbOpen" -> {
                val name = call.argument<String>("deviceName")
                val dev = usb.deviceList.values.firstOrNull { it.deviceName == name }
                if (dev == null) { result.error("usb", "Aparelho USB não encontrado", null); return }
                if (usb.hasPermission(dev)) { result.success(openUsb(dev)); return }
                pendingOpen?.error("usb", "Pedido substituído", null)
                pendingOpen = result
                pendingDevice = dev
                val intent = Intent(ACTION_USB_PERMISSION).setPackage(packageName)
                val flags = if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0
                usb.requestPermission(dev, PendingIntent.getBroadcast(this, 0, intent, flags))
            }
            "usbClose" -> { closeUsb(); result.success(null) }
            "usbSend" -> {
                val data = call.argument<ByteArray>("data")
                if (data == null || data.isEmpty()) { result.success(false); return }
                val c = conn
                val ep = epOut
                if (c == null || ep == null) { result.error("usb", "GT-1 não conectada", null); return }
                sender.execute {
                    val ok = usbWrite(c, ep, encodeUsbMidi(data))
                    main.post { result.success(ok) }
                }
            }
            "bleScanStart" -> {
                val err = bleScanStart()
                if (err == null) result.success(null) else result.error("ble", err, null)
            }
            "bleScanStop" -> { bleScanStop(); result.success(null) }
            "midiList" -> {
                val mm = midiManager
                if (mm == null) { result.success(emptyList<Any>()); return }
                @Suppress("DEPRECATION")
                val list = mm.devices.filter { it.outputPortCount > 0 && it.type != MidiDeviceInfo.TYPE_VIRTUAL }
                result.success(list.map { mapOf("id" to it.id, "name" to deviceName(it), "transport" to transport(it)) })
            }
            "pedalOpenBle" -> pedalOpenBle(call.argument<String>("address") ?: "", result)
            "pedalOpenMidi" -> pedalOpenMidi(call.argument<Int>("id") ?: -1, result)
            "pedalClose" -> { closePedal(); result.success(null) }
            else -> result.notImplemented()
        }
    }

    // ------------------------------------------------------------------ USB: GT-1
    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            when (intent.action) {
                ACTION_USB_PERMISSION -> {
                    val dev = pendingDevice
                    val r = pendingOpen
                    pendingDevice = null
                    pendingOpen = null
                    if (dev == null || r == null) return
                    val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                    if (granted || usb.hasPermission(dev)) r.success(openUsb(dev))
                    else r.error("usb", "Permissão de USB negada", null)
                }
                UsbManager.ACTION_USB_DEVICE_ATTACHED -> emit(mapOf("type" to "usbAttached"))
                UsbManager.ACTION_USB_DEVICE_DETACHED -> {
                    val dev = usbDeviceFrom(intent)
                    if (dev != null && dev.deviceName == openedName) {
                        closeUsb()
                        status("usb", "disconnected", "Cabo USB desconectado")
                    }
                }
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun usbDeviceFrom(intent: Intent): UsbDevice? {
        return if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
        } else {
            intent.getParcelableExtra<UsbDevice>(UsbManager.EXTRA_DEVICE)
        }
    }

    /** Procura a interface com um par de endpoints bulk/interrupt (a interface MIDI da GT-1). */
    private fun openUsb(dev: UsbDevice): Map<String, Any?> {
        closeUsb()
        var chosen: UsbInterface? = null
        var chosenIn: UsbEndpoint? = null
        var chosenOut: UsbEndpoint? = null
        var bestScore = -1
        for (i in 0 until dev.interfaceCount) {
            val itf = dev.getInterface(i)
            var inE: UsbEndpoint? = null
            var outE: UsbEndpoint? = null
            for (e in 0 until itf.endpointCount) {
                val ep = itf.getEndpoint(e)
                val t = ep.type
                if (t != UsbConstants.USB_ENDPOINT_XFER_BULK && t != UsbConstants.USB_ENDPOINT_XFER_INT) continue
                if (ep.direction == UsbConstants.USB_DIR_IN) { if (inE == null) inE = ep } else { if (outE == null) outE = ep }
            }
            if (inE == null || outE == null) continue
            var score = 1
            if (itf.interfaceClass == UsbConstants.USB_CLASS_VENDOR_SPEC) score += 2
            if (itf.interfaceClass == UsbConstants.USB_CLASS_AUDIO && itf.interfaceSubclass == 3) score += 3
            if (inE.type == UsbConstants.USB_ENDPOINT_XFER_BULK) score += 1
            if (score > bestScore) {
                bestScore = score; chosen = itf; chosenIn = inE; chosenOut = outE
            }
        }
        val itf = chosen
        val inE = chosenIn
        val outE = chosenOut
        if (itf == null || inE == null || outE == null) {
            return mapOf("ok" to false, "error" to "Não encontrei a interface MIDI neste aparelho USB")
        }
        val c = usb.openDevice(dev) ?: return mapOf("ok" to false, "error" to "O Android não abriu o aparelho USB")
        if (!c.claimInterface(itf, true)) {
            c.close()
            return mapOf("ok" to false, "error" to "Não consegui assumir a interface USB")
        }
        if (itf.alternateSetting != 0) c.setInterface(itf)
        conn = c; usbIface = itf; epIn = inE; epOut = outE; openedName = dev.deviceName
        startReader(c, inE)
        return mapOf(
            "ok" to true,
            "name" to (dev.productName ?: "GT-1"),
            "detail" to "interface ${itf.id}/${itf.alternateSetting} classe ${itf.interfaceClass} " +
                "in 0x${Integer.toHexString(inE.address)} out 0x${Integer.toHexString(outE.address)}",
        )
    }

    private fun closeUsb() {
        reading = false
        try { reader?.join(400) } catch (_: Exception) {}
        reader = null
        val c = conn
        val itf = usbIface
        if (c != null) {
            try { if (itf != null) c.releaseInterface(itf) } catch (_: Exception) {}
            try { c.close() } catch (_: Exception) {}
        }
        conn = null; usbIface = null; epIn = null; epOut = null; openedName = null
    }

    private fun usbWrite(c: UsbDeviceConnection, ep: UsbEndpoint, packets: ByteArray): Boolean {
        val chunk = maxOf(4, (ep.maxPacketSize / 4) * 4)
        var off = 0
        while (off < packets.size) {
            val len = minOf(chunk, packets.size - off)
            val n = c.bulkTransfer(ep, packets, off, len, 1000)
            if (n < 0) return false
            off += len
        }
        return true
    }

    /** Converte uma mensagem MIDI em pacotes USB-MIDI (cabo 0). */
    private fun encodeUsbMidi(d: ByteArray): ByteArray {
        val out = ByteArrayOutputStream()
        val status = d[0].toInt() and 0xFF
        if (status == 0xF0) {
            var i = 0
            while (i < d.size) {
                val left = d.size - i
                if (left > 3) {
                    out.write(0x04); out.write(d, i, 3); i += 3
                } else {
                    out.write(when (left) { 1 -> 0x05; 2 -> 0x06; else -> 0x07 })
                    out.write(d, i, left)
                    repeat(3 - left) { out.write(0) }
                    i += left
                }
            }
        } else {
            val n = minOf(3, d.size)
            out.write(status shr 4)
            out.write(d, 0, n)
            repeat(3 - n) { out.write(0) }
        }
        return out.toByteArray()
    }

    /** Lê pacotes USB-MIDI da GT-1 e entrega mensagens completas ao Flutter. */
    private fun startReader(c: UsbDeviceConnection, ep: UsbEndpoint) {
        reading = true
        reader = Thread {
            val buf = ByteArray(maxOf(64, ep.maxPacketSize))
            val sysex = ByteArrayOutputStream()
            while (reading) {
                val n = c.bulkTransfer(ep, buf, buf.size, 200)
                if (n <= 0) continue
                var i = 0
                while (i + 4 <= n) {
                    val cin = buf[i].toInt() and 0x0F
                    val b1 = buf[i + 1].toInt() and 0xFF
                    val b2 = buf[i + 2].toInt() and 0xFF
                    val b3 = buf[i + 3].toInt() and 0xFF
                    when (cin) {
                        0x4 -> { sysex.write(b1); sysex.write(b2); sysex.write(b3) }
                        0x5 -> { sysex.write(b1); flushSysex(sysex) }
                        0x6 -> { sysex.write(b1); sysex.write(b2); flushSysex(sysex) }
                        0x7 -> { sysex.write(b1); sysex.write(b2); sysex.write(b3); flushSysex(sysex) }
                        0x8, 0x9, 0xA, 0xB, 0xE -> emitGt(byteArrayOf(b1.toByte(), b2.toByte(), b3.toByte()))
                        0xC, 0xD -> emitGt(byteArrayOf(b1.toByte(), b2.toByte()))
                        else -> {}
                    }
                    i += 4
                }
            }
        }.apply { isDaemon = true; name = "gt1-reader"; start() }
    }

    private fun flushSysex(sysex: ByteArrayOutputStream) {
        val bytes = sysex.toByteArray()
        sysex.reset()
        if (bytes.isNotEmpty() && (bytes[0].toInt() and 0xFF) == 0xF0) emitGt(bytes)
    }

    private fun emitGt(bytes: ByteArray) = emit(mapOf("type" to "gt", "data" to bytes))

    // ------------------------------------------------------------------ Pedal: Bluetooth LE MIDI
    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, r: ScanResult) {
            val d = r.device ?: return
            val address = d.address ?: return
            val name = r.scanRecord?.deviceName ?: d.name ?: ""
            val isMidi = r.scanRecord?.serviceUuids?.contains(MIDI_SERVICE_UUID) == true
            if (!isMidi && !PEDAL_NAME.containsMatchIn(name)) return
            if (seenBle.containsKey(address)) return
            seenBle[address] = d
            emit(mapOf("type" to "ble", "address" to address, "name" to name.ifEmpty { "Pedal Bluetooth MIDI" }))
        }

        override fun onScanFailed(errorCode: Int) {
            scanning = false
            status("pedal", "error", "A busca Bluetooth falhou (código $errorCode)")
        }
    }

    private fun bleScanStart(): String? {
        val bm = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager?
        val ad = bm?.adapter ?: return "Este aparelho não tem Bluetooth"
        if (!ad.isEnabled) return "Ligue o Bluetooth do celular"
        val sc = ad.bluetoothLeScanner ?: return "Bluetooth LE indisponível"
        bleScanStop()
        seenBle.clear()
        scanner = sc
        val settings = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build()
        sc.startScan(null, settings, scanCallback)
        scanning = true
        main.postDelayed({ bleScanStop() }, 20000)
        return null
    }

    private fun bleScanStop() {
        if (scanning) {
            try { scanner?.stopScan(scanCallback) } catch (_: Exception) {}
        }
        scanning = false
    }

    private fun pedalOpenBle(address: String, result: MethodChannel.Result) {
        val mm = midiManager ?: return result.error("midi", "Este celular não tem suporte a MIDI", null)
        bleScanStop()
        val bm = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager?
        val dev = seenBle[address] ?: bm?.adapter?.getRemoteDevice(address)
        if (dev == null) { result.error("ble", "Pedal não encontrado", null); return }
        closePedal()
        mm.openBluetoothDevice(dev, { d ->
            if (d == null) result.error("ble", "Não consegui conectar ao pedal pelo Bluetooth", null)
            else attachPedal(d, result)
        }, main)
    }

    private fun pedalOpenMidi(id: Int, result: MethodChannel.Result) {
        val mm = midiManager ?: return result.error("midi", "Este celular não tem suporte a MIDI", null)
        @Suppress("DEPRECATION")
        val info = mm.devices.firstOrNull { it.id == id }
        if (info == null) { result.error("midi", "Dispositivo MIDI não encontrado", null); return }
        closePedal()
        mm.openDevice(info, { d ->
            if (d == null) result.error("midi", "Não consegui abrir o dispositivo MIDI", null)
            else attachPedal(d, result)
        }, main)
    }

    private fun attachPedal(d: MidiDevice, result: MethodChannel.Result) {
        val info = d.info
        if (info.outputPortCount < 1) {
            try { d.close() } catch (_: Exception) {}
            result.error("midi", "Esse dispositivo não envia MIDI", null)
            return
        }
        val port = d.openOutputPort(0)
        if (port == null) {
            try { d.close() } catch (_: Exception) {}
            result.error("midi", "Não consegui abrir a porta do pedal", null)
            return
        }
        port.connect(pedalReceiver)
        pedalDevice = d
        pedalPort = port
        result.success(mapOf("name" to deviceName(info), "id" to info.id))
    }

    private fun closePedal() {
        try { pedalPort?.disconnect(pedalReceiver) } catch (_: Exception) {}
        try { pedalPort?.close() } catch (_: Exception) {}
        try { pedalDevice?.close() } catch (_: Exception) {}
        pedalPort = null
        pedalDevice = null
    }

    @Suppress("DEPRECATION")
    private val midiCallback = object : MidiManager.DeviceCallback() {
        override fun onDeviceRemoved(device: MidiDeviceInfo) {
            if (pedalDevice?.info?.id == device.id) {
                closePedal()
                status("pedal", "disconnected", "O pedal desconectou")
            }
        }
    }

    /** Separa o fluxo de bytes do pedal em mensagens (com running status). */
    private val pedalReceiver = object : MidiReceiver() {
        private var running = 0
        private val msg = ByteArrayOutputStream()
        private var need = 0
        private var inSysex = false

        override fun onSend(data: ByteArray, offset: Int, count: Int, timestamp: Long) {
            for (k in offset until offset + count) {
                val b = data[k].toInt() and 0xFF
                if (b >= 0xF8) continue // clock, active sensing
                if (inSysex) {
                    msg.write(b)
                    if (b == 0xF7) { inSysex = false; emitPedal() }
                    continue
                }
                if (b == 0xF0) { msg.reset(); msg.write(b); inSysex = true; continue }
                if (b >= 0x80) {
                    msg.reset()
                    if (b >= 0xF0) { running = 0; continue }
                    running = b
                    msg.write(b)
                    val hi = b shr 4
                    need = if (hi == 0xC || hi == 0xD) 1 else 2
                    continue
                }
                if (msg.size() == 0) {
                    if (running == 0) continue
                    msg.write(running)
                    val hi = running shr 4
                    need = if (hi == 0xC || hi == 0xD) 1 else 2
                }
                msg.write(b)
                need--
                if (need == 0) emitPedal()
            }
        }

        private fun emitPedal() {
            val bytes = msg.toByteArray()
            msg.reset()
            emit(mapOf("type" to "pedal", "data" to bytes))
        }
    }

    // ------------------------------------------------------------------ utilitários
    private fun deviceName(info: MidiDeviceInfo): String {
        val p = info.properties
        return p.getString(MidiDeviceInfo.PROPERTY_NAME)
            ?: p.getString(MidiDeviceInfo.PROPERTY_PRODUCT)
            ?: "MIDI ${info.id}"
    }

    private fun transport(info: MidiDeviceInfo): String = when (info.type) {
        MidiDeviceInfo.TYPE_USB -> "usb"
        MidiDeviceInfo.TYPE_BLUETOOTH -> "ble"
        else -> "outro"
    }

    private fun hex4(v: Int) = String.format("%04X", v)
}
