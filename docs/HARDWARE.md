# Camp Colt Hardware & Physical Specifications

This document details the physical packaging, 3D-printable mounting models (STLs/CAD), power envelope, and thermal design for **Camp Colt** (Suitcase AI).

---

## 📐 Physical Enclosure: 10" Mini-Rack (8U)

The cluster is housed in an open, modular 10-inch desktop rack based on the **ButterflyRack** architecture with integrated vertical metal rack rails.

- **Form Factor:** 10-inch mini-rack standard (approximately 254 mm rail-to-rail hole center spacing).
- **Height:** 8 Rack Units (8U, ~355 mm total usable vertical height).
- **Depth:** 220 mm to 260 mm usable chassis depth.
- **Upstream 3D Models & STLs:**
  - **Rack Enclosure:** [ButterflyRack by axiopaladin (GitHub)](https://github.com/axiopaladin/ButterflyRack) — modular 3D-printable 10" rack frames, base corners, and handles.
  - **Rack Mounting Standard:** Standard 10" rack ear patterns (M5/M6 cage nuts or threaded rails).

---

## 🗄️ Rack Elevation & Physical BOM

```text
┌─────────────────────────────────────────────────────────────┐
│ 8U 10" Mini-Rack (axiopaladin/ButterflyRack w/ Metal Rails) │
├─────┬───────────────────────────────────────────────────────┤
│ 7-8U│ ASUS Ascent GX10 (NVIDIA Grace Blackwell GB10, 128GB) │
│     │ + 4TB USB NVMe SSD (Local Model Weight Cache)         │
├─────┼───────────────────────────────────────────────────────┤
│ 6U  │ 14-Port Keystone Patch Panel                          │
├─────┼───────────────────────────────────────────────────────┤
│ 5U  │ 1G Managed Switch (10.82.0.0/16 Network Fabric)       │
├─────┼───────────────────────────────────────────────────────┤
│ 3-4U│ Minisforum UM760 Slim (AMD Ryzen 5 7640HS, 32GB DDR5) │
│     │ [ Proxmox VE 9.2 Hypervisor • colt-cp-01 ]            │
├─────┼───────────────────────────────────────────────────────┤
│ 1-2U│ [ Base Shelf / PDU Power Distribution & Bricks ]      │
└─────┴───────────────────────────────────────────────────────┘
```

### Bill of Materials (BOM) & Parts List

| Component                   | Hardware Model                                                   | Physical Dimensions / Mount                          | Key Specs / Power                                               |
| :-------------------------- | :--------------------------------------------------------------- | :--------------------------------------------------- | :-------------------------------------------------------------- |
| **Chassis**                 | [ButterflyRack 8U](https://github.com/axiopaladin/ButterflyRack) | 10" desktop rack (3D printed PETG/ABS + metal rails) | 8U capacity, open convective airflow                            |
| **GPU Inference Host**      | ASUS Ascent GX10                                                 | 2U custom vented shelf (`7-8U`)                      | NVIDIA Grace Blackwell GB10, 128GB unified RAM (~140W–220W TDP) |
| **Model Weight Cache**      | 4TB USB NVMe SSD                                                 | Adhesive bracket / shelf mount (`7-8U`)              | USB 3.2 Gen2 (10Gbps) external NVMe drive (~5W–8W)              |
| **Patch Panel**             | 14-Port 10" Keystone Panel                                       | 1U 10" metal/printed panel (`6U`)                    | Cat6 RJ-45 shielded keystone couplers                           |
| **Network Switch (`SW07`)** | Netgear GS108E (8-Port Gigabit Plus, non-PoE)                    | 1U 10" shelf mount (`5U`)                            | 8-port Gigabit (802.1Q VLAN support, ~4W max)                   |
| **Hypervisor Host**         | Minisforum UM760 Slim (or MS-01)                                 | 1.5U–2U tray (`3-4U`)                                | AMD Ryzen 5 7640HS, 32GB DDR5, 1TB NVMe, 2.5GbE (~35W–65W)      |
| **Power Distribution**      | Compact PDU / Power Strip                                        | 1U base shelf (`1-2U`)                               | 120V / 15A input, NEMA 5-15R outlets + OEM DC power bricks      |

---

## 🖨️ 3D Printing & CAD Mount Files

Where custom brackets and adapters are used, models are designed with **OpenSCAD** and parameterized using the [BOSL2](https://github.com/BelfrySCAD/BOSL2) library. (Note: `SW07` rests on a 1U 10" printed shelf).

### Print Settings & Filament Guidelines

- **Material:** PETG or ABS/ASA recommended (due to proximity to GPU and hypervisor exhaust thermals). PLA is discouraged for shelf brackets directly adjacent to the GX10.
- **Infill:** 25%–40% Gyroid for shelves and structural brackets; 100% infill for keystone clips and rail mounting tabs.
- **Layer Height:** 0.20 mm standard.
- **Perimeters:** 4 perimeters minimum for all load-bearing screw holes and rail mount lugs.

---

## ⚡ Electrical & Power Budget (120V / 15A Circuit)

The entire appliance is engineered to operate comfortably within a standard **North American 120V / 15A household branch circuit** (1,800W continuous max / 1,440W at 80% NEC derating):

| Subsystem                                   | Idle Power  | Typical Load | Peak Draw  |
| :------------------------------------------ | :---------- | :----------- | :--------- |
| **Minisforum Hypervisor (`colt-cp-01`)**    | ~12 W       | ~35 W        | ~65 W      |
| **ASUS Ascent GX10 (`colt-gpu-01`)**        | ~30 W       | ~140 W       | ~220 W     |
| **8-Port Managed Switch (`SW07` - GS108E)** | ~1.5 W      | ~2.5 W       | ~4 W       |
| **4TB NVMe SSD Cache**                      | ~1 W        | ~4 W         | ~8 W       |
| **Total Appliance Draw**                    | **~44.5 W** | **~181.5 W** | **~297 W** |

> [!NOTE]
> Under full continuous synthetic LLM inference (vLLM batch execution on Grace Blackwell GB10), total power draw remains under **300 Watts** (~2.5 Amps at 120V). This leaves ample margin for portable generator operation or battery-backed UPS runtimes.

---

## ❄️ Thermal & Airflow Design

1. **Convective Chimney Effect:**
   - The ButterflyRack's open sides and vented base permit ambient air intake from the bottom (1–2U) through the shelf perforated grid.
   - Hot air generated by the Ryzen 7640HS blower and GX10 chassis rises naturally through the top of the rack.
2. **Exhaust Clearance (7–8U):**
   - The top 2U (`7-8U`) houses the GX10. Its exhaust vents directly upward and out through the top rack opening, preventing heat soak into the network switch or hypervisor below.
