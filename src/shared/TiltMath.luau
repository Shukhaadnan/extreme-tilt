-- TiltMath: pure maths for the tilting plate (no Roblox types, so luau.exe can test it offline).
-- Tilt vectors are in DEGREES and point toward the side of the plate that dips (the heavy side).
local TiltMath = {}

-- bodies: array of { x = number, z = number, w = number } (offsets from the plate centre)
function TiltMath.torque(bodies)
	local tx, tz = 0, 0
	for _, b in ipairs(bodies) do
		local w = b.w or 1
		tx += (b.x or 0) * w
		tz += (b.z or 0) * w
	end
	return tx, tz
end

function TiltMath.magnitude(x, z)
	return math.sqrt(x * x + z * z)
end

-- torque -> wanted tilt vector, clamped to maxTilt degrees
function TiltMath.target(tx, tz, perUnit, maxTilt)
	local ax, az = tx * perUnit, tz * perUnit
	local m = math.sqrt(ax * ax + az * az)
	if m > maxTilt and m > 0 then
		local s = maxTilt / m
		ax, az = ax * s, az * s
	end
	return ax, az
end

-- move the current tilt vector toward the wanted one by at most rate*dt degrees
function TiltMath.approach(cx, cz, ax, az, rate, dt)
	local dx, dz = ax - cx, az - cz
	local d = math.sqrt(dx * dx + dz * dz)
	local step = rate * dt
	if d <= step or d == 0 then
		return ax, az
	end
	local s = step / d
	return cx + dx * s, cz + dz * s
end

-- tilt vector -> rotation axis (unit x, z; y = 0) and angle in RADIANS.
-- Rotating the flat plate by this makes the side the vector points at go DOWN.
function TiltMath.axisAngle(vx, vz)
	local m = math.sqrt(vx * vx + vz * vz)
	if m < 1e-4 then
		return 1, 0, 0
	end
	local dx, dz = vx / m, vz / m
	return dz, -dx, math.rad(m)
end

-- how fast something standing on a plate tilted `angleDeg` slides downhill (studs/s)
function TiltMath.slideSpeed(angleDeg, deadzone, k, cap)
	if angleDeg <= deadzone then
		return 0
	end
	local s = k * (math.sin(math.rad(angleDeg)) - math.sin(math.rad(deadzone)))
	if cap and s > cap then
		s = cap
	end
	if s < 0 then
		s = 0
	end
	return s
end

-- angle in degrees between a unit up-vector (nx, ny, nz) and straight up
function TiltMath.angleFromNormal(ny)
	if ny > 1 then
		ny = 1
	elseif ny < -1 then
		ny = -1
	end
	return math.deg(math.acos(ny))
end

-- where a balancing bot should stand: opposite the heavy side, further out the heavier it is.
-- ox, oz = torque from everything except this bot. Returns an offset (x, z) from the centre.
function TiltMath.balanceSpot(ox, oz, spread, minR, maxR, gain)
	local m = math.sqrt(ox * ox + oz * oz)
	if m < 1e-3 then
		return 0, 0
	end
	local ang = math.atan2(-oz, -ox) + (spread or 0)
	local r = math.clamp(minR + m * gain, minR, maxR)
	return math.cos(ang) * r, math.sin(ang) * r
end

function TiltMath.lerp(a, b, t)
	return a + (b - a) * math.clamp(t, 0, 1)
end

-- seconds -> "m:ss"
function TiltMath.clock(s)
	s = math.max(0, math.floor(s + 0.5))
	return string.format("%d:%02d", s // 60, s % 60)
end

return TiltMath
