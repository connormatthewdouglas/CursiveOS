#!/bin/bash
echo "=== CursiveOS Benchmark v0.1 (AMD CPU + Intel GPU edition) ==="
echo "Testing before/after Linux tweaks for Bittensor mining"
echo ""

# Baseline
echo "BASELINE (current speed):"
sensors | grep -E 'Core|Package|temp' | head -n 4 || echo "CPU temps not detected yet"
sysbench --test=cpu --cpu-max-prime=20000 --num-threads=$(nproc) run | grep "events per second"

# Apply safe CursiveOS tweak #1 (performance mode — perfect for AMD CPUs)
echo ""
echo "Applying CursiveOS tweak: CPU performance governor..."
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor > /dev/null

# Re-test
echo ""
echo "AFTER CursiveOS TWEAK:"
sensors | grep -E 'Core|Package|temp' | head -n 4 || echo "CPU temps not detected yet"
sysbench --test=cpu --cpu-max-prime=20000 --num-threads=$(nproc) run | grep "events per second"

echo ""
echo "✅ CursiveOS v0.1 complete!"
echo "Higher 'events per second' = faster CPU = more TAO per day when you mine."
echo "Note: Reboot to reset to normal power-saving mode."
