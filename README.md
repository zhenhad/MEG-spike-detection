from pathlib import Path

readme = r"""# MEG Spike Detection with FAMED

Replication and adaptation of the deep-learning MEG spike detection and segmentation framework described by **Hirano et al. (2022)** for a six-subject MEG dataset.

This repository documents the full workflow from **Brainstorm/MATLAB preprocessing** to **Python/PyTorch transfer learning, subject-wise cross-validation, out-of-fold threshold selection, and a locked held-out evaluation on BCH001**.

> **Important:** This project is a research replication/adaptation, not an exact reproduction of the original Hirano pipeline. The BCH sensor mapping and segmentation labels differ from the original study, and equivalent-current-dipole (ECD) localization is not evaluated here.

---

## Reference study

This project is based on:

**Hirano R, Emura T, Nakata O, et al.**  
*Fully-Automated Spike Detection and Dipole Analysis of Epileptic MEG Using Deep Learning.*  
IEEE Transactions on Medical Imaging. 2022;41(10):2879-2890.  
DOI: `10.1109/TMI.2022.3173743`

The original study introduced a deep-learning framework for automated interictal MEG spike detection, sensor-level segmentation, and dipole analysis.

This repository focuses on the **spike classification and segmentation components**.

---

# Project goals

The main goals of this project were to:

1. reproduce the released FAMED model architecture and inference workflow;
2. adapt the pretrained model to Neuromag MEG recordings;
3. construct spike and control windows from six subjects;
4. create a common 234-row input representation across subjects;
5. fine-tune the classifier and segmentation network using transfer learning;
6. improve robustness using training-only augmentation;
7. evaluate performance with subject-wise cross-validation;
8. select the segmentation threshold using development-set out-of-fold predictions only;
9. perform a locked final evaluation on a held-out subject.

---

# Dataset

Six subjects were included:

- `BCH001`
- `BCH007`
- `BCH009`
- `BCH010`
- `BCH012`
- `BCH017`

The final dataset contains:

| Class | Windows |
|---|---:|
| Spike | 118 |
| Control | 170 |
| **Total** | **288** |

Each model input has shape:

```text
234 × 1024
```

corresponding to approximately:

```text
234 model-input rows
1024 time samples
1000 Hz sampling rate
~1.024 s per window
```

## Final held-out test subject

`BCH001` was reserved as the final test subject:

| BCH001 | Windows |
|---|---:|
| Spike | 29 |
| Control | 36 |
| **Total** | **65** |

The remaining subjects were used for model development and cross-validation.

---

# Full processing pipeline

The project contains two major stages:

1. **Brainstorm + MATLAB preprocessing and dataset construction**
2. **Python / PyTorch FAMED training and evaluation**

---

# Stage 1 — Brainstorm and MATLAB preprocessing

The original MEG recordings and expert annotations were first inspected and processed using **Brainstorm** and MATLAB.

## Step 1 — Inspect recordings and spike annotations

Relevant exploratory code:

```text
opening.m
```

Brainstorm was used to inspect:

- continuous MEG recordings;
- expert-marked interictal epileptiform discharges;
- event timing;
- trial definitions;
- sensor information;
- PSD results;
- Brainstorm data structures.

---

## Step 2 — Create and inspect segmentation masks

Initial mask-related scripts:

```text
seg_mask.m
Segmentation_mask.m
```

The segmentation masks identify MEG channels associated with each annotated spike within approximately:

```text
-60 ms to +60 ms
```

around the event.

These BCH masks are based on high-power sensor activity and therefore represent **proxy segmentation labels**, not the ECD-selected labels used in the original Hirano study.

---

## Step 3 — Select high-power MEG channels

```text
select_high_power_channels.m
```

For each spike trial, channel power was evaluated using Brainstorm PSD results.

High-power channels were selected using the project-specific percentile criterion and were then used to construct the segmentation masks.

---

## Step 4 — Verify spike timing in the original raw MEG

```text
first_verify_raw_spike.m
```

This step verifies that the event marked in the Brainstorm trial corresponds to the correct absolute time point in the original continuous MEG recording.

This was necessary before extracting the final FAMED-aligned window.

---

## Step 5 — Check channel consistency across subjects

```text
Second_check_channel_mapping.m
```

This script compares MEG channel names and channel availability across the six subjects.

A channel inventory was generated:

```text
MEG_channel_inventory.csv
```

This step identified the Neuromag sensors consistently available across subjects.

---

## Step 6 — Create the common 234-row FAMED channel map

```text
third_create_channel_map_234.m
```

A common 234-row model-input representation was constructed from the shared Neuromag channels.

Outputs include:

```text
FAMED_channel_map_234.csv
FAMED_channel_map_234.mat
```

The same mapping is applied to both:

```text
MEG signal
segmentation mask
```

for every subject.

> The exact original Hirano 160-to-234 mapping was not available, so this should be considered a reproducible project-specific adaptation.

---

## Step 7 — Extract and align positive spike windows

Initial implementation:

```text
fourth_batch_extract_aligned_famed.m
```

Final corrected implementation:

```text
fourth_batch_extract_aligned_famed_fixed.m
```

This stage:

1. reads the original continuous MEG signal;
2. identifies the absolute spike time;
3. extracts a 1.024-s window centered on the event;
4. resamples/interpolates the signal to the required 1000-Hz time grid;
5. applies the shared 234-row channel mapping;
6. aligns the segmentation mask to the same time grid.

Example intermediate output:

```text
BCH001_Trial001_aligned_234.mat
```

The final aligned positive examples contain:

```text
X234      -> MEG signal
Yseg234   -> segmentation mask
```

with shape:

```text
234 × 1024
```

---

## Step 8 — Extract spike-free control windows

Initial five-subject implementation:

```text
fifth_batch_extract_famed_controls_5_subjects.m
```

Final implementation:

```text
fifth_batch_extract_famed_controls.m
```

Control events were identified from existing spike-free annotations and extracted from the original recordings using the same alignment and 234-row mapping procedure as the positive windows.

This ensures that spike and control examples share the same:

```text
sampling rate
window duration
channel representation
signal-processing basis
```

---

# Stage 2 — Python / PyTorch FAMED pipeline

After the Brainstorm/MATLAB preprocessing stage, the aligned MEG windows were transferred to the Python pipeline.

---

## Step 12 — Build the six-subject positive dataset

```bash
python 12_build_six_subject_positive_dataset.py
```

Combines the aligned positive `.mat` files produced by MATLAB into a unified Python dataset.

Output:

```text
FAMED_six_subjects_positive_dataset/
```

Final positive dataset:

```text
118 spike windows
```

with arrays:

```text
X_positive:     118 × 234 × 1024
Yseg_positive:  118 × 234 × 1024
```

---

## Step 13 — Build the final dataset and subject-wise CV folds

```bash
python 13_build_final_famed_dataset_CrossVal.py
```

Combines:

```text
118 spike windows
170 control windows
```

to create:

```text
288 total windows
```

and applies the common preprocessing:

```text
3-35 Hz Butterworth filtering
global z-score normalization
```

Main output:

```text
FAMED_final_dataset_CV/
```

Important files include:

```text
X.npy
Yseg.npy
y.npy
subject_cv_folds.npz
sample_metadata.csv
cross_validation_folds.csv
preprocessing_and_cv.json
```

## Cross-validation design

`BCH001` is excluded from all model development.

The remaining subjects are divided into subject-disjoint development folds.

Because one development subject does not contain both classes, strict leave-one-subject-out validation was not possible. A grouped subject-wise CV design was used so that validation folds contained both spike and control examples while maintaining subject separation.

No BCH001 samples are used during:

- training;
- validation;
- early stopping;
- augmentation;
- segmentation-threshold selection.

---

## Step 14 — Fine-tune the FAMED classifier

```bash
python 14_finetune_famed_classifier_CV_aug.py
```

Each fold starts independently from the pretrained FAMED classification checkpoint.

### Training-only augmentation

The classifier uses conservative augmentation during training only:

- temporal jitter up to approximately ±50 ms;
- small channel-specific amplitude changes;
- low-amplitude Gaussian noise;
- light channel dropout.

Validation and test samples are never augmented.

### Transfer learning

The pretrained FAMED classifier weights are used as initialization and then fine-tuned using the development subjects.

Output:

```text
FAMED_classifier_CV_aug/
```

---

## Step 15 — Fine-tune the FAMED segmentation network

```bash
python 15_finetune_famed_segmentation_CV_aug.py
```

For each fold:

1. initialize the FAMED segmentation architecture;
2. load the pretrained segmentation checkpoint;
3. transfer the matching fine-tuned classifier encoder from Step 14;
4. fine-tune the segmentation network on the BCH proxy masks.

Temporal augmentation is applied jointly to the MEG signal and segmentation mask so that their alignment is preserved.

Output:

```text
FAMED_segmentation_CV_aug/
```

---

## Step 16 — Select the segmentation threshold

```bash
python 16_select_segmentation_threshold_CV.py
```

Threshold selection is performed using only **out-of-fold development predictions**.

Candidate thresholds:

```text
0.50
0.55
0.60
0.65
0.70
0.75
0.80
0.85
0.90
0.95
0.975
0.99
```

The selected threshold was:

```text
Segmentation threshold = 0.90
```

The threshold was selected by maximizing pooled out-of-fold micro Dice while including false-positive pixels from control windows.

Output:

```text
FAMED_segmentation_CV_threshold/
```

---

## Step 17 — Locked final BCH001 evaluation

First verify all folds, checkpoints, and thresholds without running inference:

```bash
python 17_final_famed_test_BCH001_CVensemble.py --check-only
```

Then run the final test:

```bash
python 17_final_famed_test_BCH001_CVensemble.py --run-final-test
```

## CV ensemble strategy

The final prediction uses the four trained CV models.

For each BCH001 window:

```text
Classifier probability
    = mean classifier probability across CV folds
```

and:

```text
Segmentation probability
    = mean pixel probability across CV segmentation folds
```

Locked thresholds:

```text
Classifier threshold   = 0.50
Segmentation threshold = 0.90
```

No retraining, threshold optimization, or test-based tuning is performed using BCH001.

Output:

```text
FAMED_final_test_BCH001_CVensemble/
```

---

## Step 18 — Generate presentation and evaluation figures

```bash
python 18_make_presentation_figures_BCH001.py
```

This script performs **no new model inference**.

It reads the saved Step 17 outputs and generates:

- classifier confusion matrix;
- ROC curve;
- precision-recall curve;
- classifier probability overview across all BCH001 windows;
- representative TP examples;
- representative FP examples;
- representative TN examples;
- difficult positive examples;
- segmentation probability maps;
- final predicted segmentation masks.

Figures are saved under:

```text
FAMED_final_test_BCH001_CVensemble/
└── presentation_figures/
```

---

# Results

## Development-set classifier performance

Pooled out-of-fold classifier performance:

| Metric | Value |
|---|---:|
| AUROC | **0.9460** |
| AUPRC | **0.9468** |
| Precision | **0.9012** |
| Recall | **0.8202** |
| F1 | **0.8588** |

These values are based exclusively on development-set out-of-fold predictions.

---

# Final held-out BCH001 results

## Classification

The CV classifier ensemble was evaluated on BCH001 using the fixed classifier threshold of `0.50`.

| Metric | BCH001 |
|---|---:|
| AUROC | **0.9962** |
| AUPRC | **0.9955** |
| Precision | **0.4915** |
| Recall | **1.0000** |
| F1 | **0.6591** |

### Confusion matrix

| | Predicted Control | Predicted Spike |
|---|---:|---:|
| **True Control** | 6 | 30 |
| **True Spike** | 0 | 29 |

The classifier achieved perfect sensitivity on the held-out spike windows.

The lower precision at the fixed `0.50` threshold reflects a relatively large number of false-positive control windows.

The classifier threshold was **not changed after observing BCH001**.

---

# Segmentation results

The segmentation threshold was fixed at:

```text
0.90
```

before evaluating BCH001.

## Standalone segmentation

| Metric | Value |
|---|---:|
| Dice | **0.4761** |
| Precision | **0.5681** |
| Recall | **0.4098** |

## Classifier-gated segmentation

| Metric | Value |
|---|---:|
| Dice | **0.4823** |
| Precision | **0.5862** |
| Recall | **0.4098** |

Classifier gating increased both Dice and precision without reducing segmentation recall.

---

# Example output figures

After Step 18, representative figures include:

```text
BCH001_classifier_confusion_matrix.png
BCH001_classifier_ROC_PR.png
BCH001_classifier_probability_overview.png
BCH001_representative_examples.png
```

If these figures are committed to GitHub, they can be displayed directly in the README:

```markdown
![BCH001 confusion matrix](FAMED_final_test_BCH001_CVensemble/presentation_figures/BCH001_classifier_confusion_matrix.png)

![BCH001 representative predictions](FAMED_final_test_BCH001_CVensemble/presentation_figures/BCH001_representative_examples.png)
```

---

# Repository structure

A clean organization for the repository is:

```text
MEG-spike-detection/
│
├── Model/
│
├── MATLAB_Brainstorm/
│   ├── opening.m
│   ├── seg_mask.m
│   ├── Segmentation_mask.m
│   ├── select_high_power_channels.m
│   ├── first_verify_raw_spike.m
│   ├── Second_check_channel_mapping.m
│   ├── third_create_channel_map_234.m
│   ├── fourth_batch_extract_aligned_famed.m
│   ├── fourth_batch_extract_aligned_famed_fixed.m
│   ├── fifth_batch_extract_famed_controls_5_subjects.m
│   └── fifth_batch_extract_famed_controls.m
│
├── FAMED_channel_map_234.csv
├── FAMED_channel_map_234.mat
├── MEG_channel_inventory.csv
│
├── FAMED_six_subjects_positive_dataset/
├── FAMED_final_dataset_CV/
├── FAMED_classifier_CV_aug/
├── FAMED_segmentation_CV_aug/
├── FAMED_segmentation_CV_threshold/
├── FAMED_final_test_BCH001_CVensemble/
│
├── 6 subj before CV/
├── Test level Codes/
│
├── 12_build_six_subject_positive_dataset.py
├── 13_build_final_famed_dataset_CrossVal.py
├── 14_finetune_famed_classifier_CV_aug.py
├── 15_finetune_famed_segmentation_CV_aug.py
├── 16_select_segmentation_threshold_CV.py
├── 17_final_famed_test_BCH001_CVensemble.py
├── 18_make_presentation_figures_BCH001.py
│
├── LICENSE
└── README.md
```

Large generated datasets and model checkpoints may be excluded from the public repository because of file size, privacy, or data-sharing restrictions.

---

# Complete workflow

```text
                    BRAINSTORM / MATLAB
                           │
                           ▼
              Inspect MEG + expert IED events
                      opening.m
                           │
                           ▼
             Build / inspect segmentation masks
                seg_mask.m
                Segmentation_mask.m
                           │
                           ▼
             Select high-power MEG channels
              select_high_power_channels.m
                           │
                           ▼
              Verify raw spike event timing
                first_verify_raw_spike.m
                           │
                           ▼
          Check channels across all subjects
           Second_check_channel_mapping.m
                           │
                           ▼
            Construct shared 234-row map
             third_create_channel_map_234.m
                           │
                           ▼
           Extract aligned positive windows
       fourth_batch_extract_aligned_famed_fixed.m
                           │
                           ▼
             Extract spike-free controls
          fifth_batch_extract_famed_controls.m
                           │
                           ▼
              Aligned 234 × 1024 windows
                           │
                           ▼
                        PYTHON
                           │
                           ▼
      12  Build six-subject positive dataset
                           │
                           ▼
      13  Final dataset + subject-wise CV
                           │
                           ▼
      14  Classifier transfer learning
          + training-only augmentation
                           │
                           ▼
      15  Segmentation transfer learning
          + training-only augmentation
                           │
                           ▼
      16  OOF segmentation threshold selection
                           │
                           ▼
                   threshold = 0.90
                           │
                           ▼
      17  Locked BCH001 CV-ensemble test
                           │
                           ▼
      18  Final figures + error analysis
```

---

# Software

The workflow uses:

- MATLAB
- Brainstorm
- Python
- PyTorch
- NumPy
- SciPy
- scikit-learn
- Matplotlib

The FAMED implementation is legacy research software, and the current project was developed using a Python 3.7-compatible environment.

---

# Reproducibility

The intended execution order is:

```text
Brainstorm inspection
 ↓
MATLAB mask construction
 ↓
MATLAB channel inventory/mapping
 ↓
MATLAB aligned spike extraction
 ↓
MATLAB aligned control extraction
 ↓
12  Build six-subject positive dataset
 ↓
13  Build final dataset + subject-wise CV
 ↓
14  Fine-tune classifier
 ↓
15  Fine-tune segmentation model
 ↓
16  Select segmentation threshold from OOF development predictions
 ↓
17  Run locked BCH001 CV-ensemble test
 ↓
18  Generate figures from saved final-test outputs
```

The workflow deliberately separates model development from the held-out test subject.

---

# Important limitations

1. **Small number of subjects**  
   Only six subjects are included.

2. **Single final-test subject**  
   Final generalization is evaluated on BCH001 only.

3. **Proxy segmentation labels**  
   BCH segmentation masks are based on high-power channels rather than the ECD-selected sensor masks used in the original Hirano study.

4. **Adapted sensor mapping**  
   The 234-row Neuromag mapping is project-specific because the exact original FAMED mapping was not available.

5. **Grouped subject-wise CV**  
   Strict leave-one-subject-out cross-validation was not possible because one development subject did not contain both classes.

6. **No ECD localization evaluation**  
   This project evaluates classification and sensor-level segmentation, not the complete dipole-localization stage of the original FAMED framework.

7. **Research use only**  
   The current implementation and results are experimental and are not intended for clinical diagnosis or clinical decision-making.

---

# Citation

If you use this repository, please cite the original FAMED study:

```bibtex
@article{hirano2022famed,
  title={Fully-Automated Spike Detection and Dipole Analysis of Epileptic MEG Using Deep Learning},
  author={Hirano, Ryoji and Emura, Takuto and Nakata, Otoichi and others},
  journal={IEEE Transactions on Medical Imaging},
  volume={41},
  number={10},
  pages={2879--2890},
  year={2022},
  doi={10.1109/TMI.2022.3173743}
}
```

---

# Acknowledgments

The FAMED architecture and pretrained models used as the starting point for this project were developed by **Hirano et al.**

This repository represents an independent replication and BCH-specific research adaptation of that framework.

---

# License

See [`LICENSE`](LICENSE) for the license applicable to this repository.

Original FAMED code and pretrained model components remain subject to the terms of their original release.
"""

out = Path("/mnt/data/README_updated_MEG-spike-detection.md")
out.write_text(readme, encoding="utf-8")
print(f"Created: {out}")
