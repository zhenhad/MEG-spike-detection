# MEG Spike Detection with FAMED

Replication and adaptation of the deep-learning MEG spike detection and segmentation framework described by **Hirano et al. (2022)** for a six-subject MEG dataset.

This repository documents the full workflow from MEG window construction and preprocessing to transfer learning, subject-wise cross-validation, out-of-fold threshold selection, and a locked held-out evaluation on **BCH001**.

> **Important:** This is a research replication/adaptation, not an exact reproduction of the original Hirano pipeline. The sensor mapping and segmentation labels used here differ from the original study, and equivalent-current-dipole (ECD) localization is not evaluated.

---

## Reference

This project is based on:

**Hirano R, Emura T, Nakata O, et al.**  
*Fully-Automated Spike Detection and Dipole Analysis of Epileptic MEG Using Deep Learning.*  
IEEE Transactions on Medical Imaging. 2022;41(10):2879-2890.  
DOI: `10.1109/TMI.2022.3173743`

The original study developed a deep-learning framework for automated MEG interictal spike detection, sensor-level segmentation, and dipole analysis.

This repository focuses on the **spike classification and segmentation components**.

---

# Project goals

The main goals were to:

1. reproduce the released FAMED architecture and inference workflow;
2. adapt the pretrained model to Neuromag MEG recordings;
3. construct spike and control windows from six subjects;
4. fine-tune the classifier and segmentation network using transfer learning;
5. improve robustness using training-only augmentation;
6. evaluate performance using subject-wise cross-validation;
7. select the segmentation threshold using development-set out-of-fold predictions only;
8. perform a locked final evaluation on a held-out subject.

---

# Dataset

Six subjects were included:

- `BCH001`
- `BCH007`
- `BCH009`
- `BCH010`
- `BCH012`
- `BCH017`

The complete dataset contains:

| Class | Number of windows |
|---|---:|
| Spike | 118 |
| Control | 170 |
| **Total** | **288** |

Each model input has shape:

```text
234 × 1024
```

corresponding to:

```text
234 model input rows
1024 time samples
1000 Hz sampling rate
~1.024 s per window
```

## Final held-out subject

`BCH001` was reserved for the final test:

| BCH001 | Windows |
|---|---:|
| Spike | 29 |
| Control | 36 |
| **Total** | **65** |

The remaining subjects were used for model development and cross-validation.

---

# MEG preprocessing

The BCH recordings were adapted to the FAMED input format using the following workflow:

1. reconstruct approximately 1.024-s windows around annotated spike or control events;
2. resample/interpolate to **1000 Hz** when required;
3. create a common Neuromag sensor representation across subjects;
4. map signals to the required **234-row FAMED input**;
5. apply a **3-35 Hz Butterworth band-pass filter**;
6. apply global z-score normalization to each window.

Filtering and normalization are performed during dataset construction.

They are **not repeated** during training, validation, or final testing.

---

# Sensor mapping

The released FAMED model expects a 234-row representation.

The exact preprocessing and original 160-to-234 sensor mapping used in the Hirano study were not available in the released material.

For this project, a reproducible common Neuromag mapping was therefore constructed from sensors shared across subjects.

The resulting 234-row representation should be considered a **project-specific adaptation**, rather than an exact reproduction of the original FAMED sensor mapping.

---

# Segmentation labels

The original Hirano segmentation masks were based on sensors selected using ECD-related information around each spike.

For the current dataset, segmentation masks were instead generated using **high-power MEG channels around the annotated event**.

These masks therefore represent **proxy sensor-level labels**.

They should not be interpreted as identical to the ECD-based ground truth used in the original publication.

---

# Current analysis pipeline

The current workflow is organized as sequential scripts.

---

## Step 12 — Build the six-subject positive dataset

```bash
python 12_build_six_subject_positive_dataset.py
```

Creates aligned positive MEG windows and their segmentation masks across the six subjects.

Main output:

```text
FAMED_six_subjects_positive_dataset/
```

---

## Step 13 — Build the final subject-wise CV dataset

```bash
python 13_build_final_famed_dataset_CrossVal.py
```

Creates the final spike/control dataset and subject-wise cross-validation folds.

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

### Cross-validation design

`BCH001` is excluded from all model development.

The remaining subjects are divided into subject-disjoint development folds.

Because one development subject does not contain both classes, strict leave-one-subject-out validation was not possible. A grouped subject-wise CV design was therefore used so that validation folds contain both spike and control examples while maintaining subject separation.

No BCH001 samples are used during:

- model training;
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

The classifier uses conservative augmentation during training:

- temporal jitter up to approximately ±50 ms;
- small channel-specific amplitude changes;
- low-amplitude Gaussian noise;
- light channel dropout.

Validation and test samples are never augmented.

### Transfer learning

The pretrained FAMED classifier is used as initialization and then fine-tuned using the development subjects.

Main output:

```text
FAMED_classifier_CV_aug/
```

---

## Step 15 — Fine-tune the segmentation model

```bash
python 15_finetune_famed_segmentation_CV_aug.py
```

For each fold:

1. initialize the FAMED segmentation architecture;
2. load the original pretrained segmentation checkpoint;
3. transfer the corresponding fine-tuned classifier encoder from Step 14;
4. fine-tune the segmentation network on the BCH proxy masks.

Temporal augmentation is applied jointly to the MEG signal and segmentation mask so that their alignment is preserved.

Main output:

```text
FAMED_segmentation_CV_aug/
```

---

## Step 16 — Select the segmentation threshold

```bash
python 16_select_segmentation_threshold_CV.py
```

Segmentation threshold selection is performed using only **out-of-fold development predictions**.

Tested thresholds:

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

Main output:

```text
FAMED_segmentation_CV_threshold/
```

---

## Step 17 — Locked final BCH001 evaluation

Before evaluating BCH001:

```bash
python 17_final_famed_test_BCH001_CVensemble.py --check-only
```

This verifies the:

- CV folds;
- classifier checkpoints;
- segmentation checkpoints;
- final-test indices;
- locked thresholds.

It does not run BCH001 inference.

The final test is then run once:

```bash
python 17_final_famed_test_BCH001_CVensemble.py --run-final-test
```

## CV ensemble

The final prediction uses the four trained CV models.

For every BCH001 window:

```text
Classifier probability
    = mean classifier probability across the CV models
```

and:

```text
Segmentation probability
    = mean pixel probability across the CV segmentation models
```

Locked thresholds:

```text
Classifier threshold   = 0.50
Segmentation threshold = 0.90
```

No retraining, threshold optimization, or test-based tuning is performed using BCH001.

Main output:

```text
FAMED_final_test_BCH001_CVensemble/
```

---

## Step 18 — Generate final-test figures

```bash
python 18_make_presentation_figures_BCH001.py
```

This script performs **no new model inference**.

It uses the saved Step 17 outputs to generate:

- classifier confusion matrix;
- ROC curve;
- precision-recall curve;
- classifier probabilities across all BCH001 windows;
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

These results are based exclusively on development-set out-of-fold predictions.

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

Importantly, the classifier threshold was **not changed after examining BCH001**.

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

After Step 18, examples include:

```text
BCH001_classifier_confusion_matrix.png
BCH001_classifier_ROC_PR.png
BCH001_classifier_probability_overview.png
BCH001_representative_examples.png
```

If the figures are committed to GitHub, they can be shown directly in this README:

```markdown
![BCH001 confusion matrix](FAMED_final_test_BCH001_CVensemble/presentation_figures/BCH001_classifier_confusion_matrix.png)

![BCH001 representative predictions](FAMED_final_test_BCH001_CVensemble/presentation_figures/BCH001_representative_examples.png)
```

---

# Repository structure

```text
MEG-spike-detection/
│
├── Model/
│
├── FAMED_six_subjects_positive_dataset/
│
├── FAMED_final_dataset_CV/
│
├── FAMED_classifier_CV_aug/
│
├── FAMED_segmentation_CV_aug/
│
├── FAMED_segmentation_CV_threshold/
│
├── FAMED_final_test_BCH001_CVensemble/
│
├── 6 subj before CV/
│
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

Large generated datasets and model checkpoints may be excluded from the public repository because of file-size or data-sharing restrictions.

---

# Software

The workflow uses:

- Python
- PyTorch
- NumPy
- SciPy
- scikit-learn
- Matplotlib
- MATLAB
- Brainstorm

The FAMED implementation is legacy research software, and the current project was developed using a Python 3.7-compatible environment.

---

# Pipeline summary

```text
Raw MEG + spike/control annotations
              │
              ▼
12  Build aligned six-subject spike dataset
              │
              ▼
13  Build final dataset + subject-wise CV
              │
              ▼
14  Fine-tune classifier
    Transfer learning + training augmentation
              │
              ▼
15  Fine-tune segmentation network
    Classifier encoder transfer + augmentation
              │
              ▼
16  OOF segmentation-threshold selection
              │
              ▼
        Threshold = 0.90
              │
              ▼
17  Locked BCH001 final test
    4-model CV probability ensemble
              │
              ▼
18  Final figures and error analysis
```

---

# Limitations

1. **Small sample size**  
   The dataset includes only six subjects.

2. **Single final-test subject**  
   Generalization is evaluated on BCH001 only.

3. **Proxy segmentation ground truth**  
   The BCH masks are based on high-power channels rather than the ECD-selected sensor labels used by Hirano et al.

4. **Adapted sensor mapping**  
   The 234-row Neuromag representation is an adaptation because the exact original FAMED mapping was unavailable.

5. **Grouped subject-wise CV**  
   Strict leave-one-subject-out validation was not possible because one subject did not contain both classes.

6. **No ECD localization evaluation**  
   The current project evaluates classification and sensor-level segmentation, not the complete dipole-localization stage of the original FAMED framework.

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

This repository represents an independent replication and MEG dataset-specific adaptation of that framework.

---

# License

See [`LICENSE`](LICENSE) for the license applicable to this repository.

Original FAMED code and pretrained model components remain subject to the terms of their original release.
