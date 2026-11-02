extends RefCounted

## Signed, zero-lag normalized correlation, first 400ms, DC removed.
## Shorter signals are zero-padded; using abs() at the call site catches inversion.
static func correlation(a: AudioStreamWAV, b: AudioStreamWAV) -> float:
	var n := roundi(0.4*a.mix_rate)
	var ax := 0.0
	var bx := 0.0
	var aa := 0.0
	var bb := 0.0
	var ab := 0.0
	for i in range(n):
		var x := a.data.decode_s16(i*2)/32768.0 if i*2 < a.data.size() else 0.0
		var y := b.data.decode_s16(i*2)/32768.0 if i*2 < b.data.size() else 0.0
		ax += x
		bx += y
		aa += x*x
		bb += y*y
		ab += x*y
	return (ab-ax*bx/n)/sqrt(maxf(1e-30,(aa-ax*ax/n)*(bb-bx*bx/n)))

## Whole PCM energy in the union of +/-3% bands. Rectangular FFT, zero-padding
## to a power of two. One-sided Parseval weights include DC and Nyquist.
static func band_energy_ratio(stream: AudioStreamWAV, centers: Array) -> float:
	var count := stream.data.size()/2
	var n := 1
	while n < count: n *= 2
	var re := PackedFloat64Array()
	var im := PackedFloat64Array()
	re.resize(n)
	im.resize(n)
	for i in range(count): re[i] = stream.data.decode_s16(i*2)/32768.0
	var j := 0
	for i in range(1,n):
		var bit := n >> 1
		while j & bit:
			j ^= bit
			bit >>= 1
		j ^= bit
		if i < j:
			var value := re[i]
			re[i] = re[j]
			re[j] = value
	var width := 2
	while width <= n:
		var wr := cos(-TAU/width)
		var wi := sin(-TAU/width)
		for start in range(0,n,width):
			var ur := 1.0
			var ui := 0.0
			for k in range(width/2):
				var left := start+k
				var right := left+width/2
				var vr := re[right]*ur-im[right]*ui
				var vi := re[right]*ui+im[right]*ur
				re[right] = re[left]-vr
				im[right] = im[left]-vi
				re[left] += vr
				im[left] += vi
				var next := ur*wr-ui*wi
				ui = ur*wi+ui*wr
				ur = next
		width *= 2
	var total := 0.0
	var bands := 0.0
	for i in range(n/2+1):
		var energy := (re[i]*re[i]+im[i]*im[i])*(1.0 if i == 0 or i == n/2 else 2.0)
		total += energy
		var frequency := i*float(stream.mix_rate)/n
		for center: float in centers:
			if frequency >= center*0.97 and frequency <= center*1.03:
				bands += energy
				break
	return bands/maxf(total,1e-30)

static func low_band(stream: AudioStreamWAV, pitch: float = 1.0, gain_db: float = 0.0) -> float:
	var values := PackedFloat64Array()
	var n := mini(roundi(stream.mix_rate*0.3), ceili(stream.data.size()/2.0/pitch))
	values.resize(n)
	for i in range(n):
		var p := minf(stream.data.size()/2-1, i*pitch)
		var j := int(p)
		values[i] = lerpf(stream.data.decode_s16(j*2), stream.data.decode_s16(mini(j+1,stream.data.size()/2-1)*2), p-j)/32768.0*db_to_linear(gain_db)
	# Second-order Butterworth high-pass 30Hz then low-pass 120Hz.
	for high in [true, false]:
		var k := tan(PI*(30.0 if high else 120.0)/stream.mix_rate)
		var norm := 1.0/(1.0+sqrt(2.0)*k+k*k)
		var b0 := norm if high else k*k*norm
		var b1 := -2*b0 if high else 2*b0
		var a1 := 2.0*(k*k-1)*norm
		var a2 := (1.0-sqrt(2.0)*k+k*k)*norm
		var x1 := 0.0
		var x2 := 0.0
		var y1 := 0.0
		var y2 := 0.0
		for i in range(n):
			var x := values[i]
			var y := b0*x+b1*x1+b0*x2-a1*y1-a2*y2
			x2=x1
			x1=x
			y2=y1
			y1=y
			values[i]=y
	var window := roundi(stream.mix_rate*0.05)
	var sq := 0.0
	var largest := 0.0
	for i in range(n):
		sq += values[i]*values[i]
		if i >= window: sq -= values[i-window]*values[i-window]
		if i >= window-1: largest=maxf(largest,sq)
	return linear_to_db(sqrt(maxf(1e-20, largest/window)))

static func tone_energy(stream: AudioStreamWAV, frequency: float, start: float, seconds: float = 0.06) -> float:
	var re := 0.0
	var im := 0.0
	var n := roundi(seconds*stream.mix_rate)
	for i in range(n):
		var sample := stream.data.decode_s16((roundi(start*stream.mix_rate)+i)*2)/32768.0
		var window := 0.5-0.5*cos(TAU*i/(n-1))
		re += sample*window*cos(TAU*frequency*i/stream.mix_rate)
		im += sample*window*sin(TAU*frequency*i/stream.mix_rate)
	return sqrt(re*re+im*im)/n
static func k_coefficients(rate: int) -> Array[PackedFloat64Array]:
	var k := tan(PI * 1681.9744509555319 / rate)
	var q := 0.7071752369554193
	var vh := pow(10, 3.99984385397 / 20.0)
	var vb := pow(vh, 0.499666774155)
	var a := 1 + k / q + k * k
	var shelf := PackedFloat64Array([(vh+vb*k/q+k*k)/a, 2*(k*k-vh)/a, (vh-vb*k/q+k*k)/a, 2*(k*k-1)/a, (1-k/q+k*k)/a])
	k = tan(PI * 38.13547087613982 / rate)
	q = 0.5003270373253953
	a = 1 + k / q + k * k
	return [shelf, PackedFloat64Array([1, -2, 1, 2*(k*k-1)/a, (1-k/q+k*k)/a])]

static func k_weighted(stream: AudioStreamWAV, circular: bool, channel: int = 0, pitch: float = 1.0, gain_db: float = 0.0) -> PackedFloat64Array:
	var pcm := stream.data
	var channels := 2 if stream.stereo else 1
	var source_n := pcm.size() / (2 * channels)
	var n := int(ceil(source_n / pitch))
	var warm := mini(n, int(stream.mix_rate * 0.5)) if circular else 0
	# A zero-input tail includes energy after the last source sample for effects.
	var tail := 0 if circular else int(stream.mix_rate * 0.05)
	var data := PackedFloat64Array()
	data.resize(warm + n + tail)
	var gain := db_to_linear(gain_db)
	for i in range(warm + n):
		var position := ((i - warm + n) % n) * pitch
		var first := mini(source_n - 1, int(position))
		var second := (first + 1) % source_n if circular else mini(source_n - 1, first + 1)
		var a := pcm.decode_s16((first * channels + channel) * 2) / 32768.0
		var b := pcm.decode_s16((second * channels + channel) * 2) / 32768.0
		data[i] = lerpf(a, b, position - first) * gain
	for c in k_coefficients(stream.mix_rate):
		var x1 := 0.0
		var x2 := 0.0
		var y1 := 0.0
		var y2 := 0.0
		for i in range(data.size()):
			var x := data[i]
			var y := c[0]*x + c[1]*x1 + c[2]*x2 - c[3]*y1 - c[4]*y2
			x2 = x1
			x1 = x
			y2 = y1
			y1 = y
			data[i] = y
	return data.slice(warm)

static func k_music_rms_db(stream: AudioStreamWAV, gain_db: float = 0.0) -> float:
	var sq := 0.0
	var n := 0
	for channel in range(2 if stream.stereo else 1):
		var data := k_weighted(stream, true, channel, 1.0, gain_db)
		n = data.size()
		for value in data: sq += value * value
	# BS.1770: sum L/R channel mean squares (no divide by channel count).
	return linear_to_db(sqrt(maxf(1e-20, sq / n)))

static func k_effect_max50_db(stream: AudioStreamWAV, pitch: float = 1.0, gain_db: float = 0.0) -> float:
	var data := k_weighted(stream, false, 0, pitch, gain_db)
	var window := int(round(stream.mix_rate * 0.05))
	var sq := 0.0
	var largest := 0.0
	# Every sample offset, fixed 50ms denominator (including short effects).
	for i in range(data.size()):
		sq += data[i] * data[i]
		if i >= window: sq -= data[i-window] * data[i-window]
		if i >= window-1: largest = maxf(largest, sq)
	return linear_to_db(sqrt(maxf(1e-20, largest / window)))

static func decoded_pcm(stream: AudioStream) -> AudioStreamWAV:
	var rate := int(AudioServer.get_mix_rate())
	var count := int(round(stream.get_length() * rate))
	var playback := stream.instantiate_playback()
	playback.start()
	var pcm := PackedByteArray()
	pcm.resize(count * 4)
	var offset := 0
	while offset < count:
		var block := playback.mix_audio(1.0, mini(4096, count-offset))
		if block.is_empty(): break
		for value in block:
			pcm.encode_s16(offset*4, clampi(int(round(value.x*32768)), -32768, 32767))
			pcm.encode_s16(offset*4+2, clampi(int(round(value.y*32768)), -32768, 32767))
			offset += 1
	playback.stop()
	var result := AudioStreamWAV.new()
	result.format = AudioStreamWAV.FORMAT_16_BITS
	result.stereo = true
	result.mix_rate = rate
	result.data = pcm
	return result

