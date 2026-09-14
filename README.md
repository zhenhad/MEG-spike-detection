# Reproducing FAMED (Hirano et al., IEEE TMI 2022) on Real MEG Data

This repository documents the reproduction and adaptation of the **FAMED** deep learning framework for automated epileptic MEG spike detection and segmentation proposed by:

> Hirano R. et al., *Fully-Automated Spike Detection and Dipole Analysis of Epileptic MEG Using Deep Learning*, IEEE Transactions on Medical Imaging, 2022.

The goal was to understand the released Code Ocean implementation, reproduce the inference pipeline, and adapt it to an independent real MEG dataset.

---

## Workflow

### 1. Study the released code

- Examined the official Code Ocean capsule.
- Understood the network architecture.
- Verified model requirements:
  - Input shape: **234 × 1024**
  - Active MEG sensors: **160**
  - Classification + Segmentation networks

---

### 2. Obtain real MEG data

Since the original clinical recordings are unavailable due to patient privacy, an external real MEG dataset was used.

Dataset:

- BCH001
- Brainstorm-exported MEG recording
- 305 MEG sensors

---

### 3. Extract labeled windows

Using Brainstorm event annotations:

- 204 spike windows
- 48 control windows

Each window:

- 305 channels
- 1024 samples (1.024 s)

Saved as the master dataset.

---

### 4. Adapt the data to FAMED

The released model expects 160 active sensors embedded into a 234-row input.

Pipeline:

```
305 MEG channels
        ↓
Representative 160-channel selection
        ↓
Embed into 234 rows
        ↓
Zero-pad remaining rows
        ↓
FAMED input tensor
```

Generated:

- `famed_spikes_234.npy`
- `famed_controls_234.npy`

---

### 5. Build the evaluation dataset

Combined spike and control windows into a single evaluation tensor.

```
X : (252, 234, 1024)
y : (252,)
```

- 204 positive windows
- 48 control windows

---

### 6. Run FAMED Classification

Loaded the released Fold-9 pretrained classification checkpoint.

Results:

- ROC AUC: **0.786**
- Probabilities computed for every evaluation window.

---

### 7. Run FAMED Segmentation

Loaded the released Fold-9 segmentation checkpoint.

Generated a confidence map for every window:

```
Output:
(252, 234, 1024)
```

Each pixel represents the model confidence for a sensor-time location.

---

### 8. Back-map to the original MEG sensors

Mapped the first 160 model rows back to the original 305-channel recording to visualize predictions on the real MEG signals.

---

### 9. Visualization

Implemented a paper-style visualization that displays:

- stacked MEG waveforms
- segmentation confidence overlay
- representative

  - True Positive
  - False Positive
  - False Negative
  - True Negative

examples.

---

## Current Results

The complete inference pipeline now runs successfully:

- Brainstorm export
- Window extraction
- Sensor adaptation
- Classification
- Segmentation
- Visualization

Example segmentation output:

- localized confidence maps centered on candidate spike activity
- confidence projected back onto the original MEG channels
- paper-style waveform visualization

---

## Current Limitation

A faithful reproduction of the original paper is not yet possible because the authors did not release:

- the original patient recordings
- the preprocessing pipeline
- the exact 160-sensor → 234-row mapping

Therefore, this repository represents a **real-data adaptation** of the released FAMED model rather than an exact replication of the original study.

---

## Repository Structure

```
prepare_bch001_real.py
prepare_bch001_windows.py
select_160_channels.py
build_famed_input.py
run_classification.py
run_segmentation.py
08_visualize_segmentation_results.py

master_spike_windows.npy
master_control_windows.npy
selected_160_indices.npy

famed_spikes_234.npy
famed_controls_234.npy
```

---

## Future Work

- Investigate the original preprocessing pipeline.
- Recover or approximate the undocumented sensor mapping.
- Compare with synthetic MEG data having known ground truth.
- Evaluate newer FAMED models (2024 multi-center study).

---

## Reference

Hirano R, Emura T, Nakata O, et al.

**Fully-Automated Spike Detection and Dipole Analysis of Epileptic MEG Using Deep Learning**

IEEE Transactions on Medical Imaging, 2022.
