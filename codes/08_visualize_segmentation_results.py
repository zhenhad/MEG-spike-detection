import os
os.environ["KMP_DUPLICATE_LIB_OK"] = "TRUE"

import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import torch
from scipy import stats

from Model.FAMED_model import get_FAMED_Seg

# ============================================================
# Configuration
# ============================================================

MASTER_SPIKE = r"bch001_test\master_spike_windows.npy"
MASTER_CONTROL = r"bch001_test\master_control_windows.npy"

EVAL_WINDOWS = r"bch001_test\evaluation_windows.npy"
LABELS = r"bch001_test\evaluation_labels.npy"

PROB = r"bch001_test\famed_probabilities.npy"

SELECTED160 = r"bch001_test\selected_160_indices.npy"

CHECKPOINT = (
    r"../data/model_weights/FAMED/"
    r"FAMED_Segmentation_Weight_Fold9.ckpt"
)

OUTPUT_DIR = os.path.join(os.getcwd(), "paper_style")

os.makedirs(OUTPUT_DIR, exist_ok=True)

# ============================================================
# Parameters
# ============================================================

FS = 600.0                  # Hz

WINDOW = 1024

CENTER = WINDOW // 2

HALF_WINDOW_MS = CENTER / FS * 1000

TIME_MS = (
    np.arange(WINDOW) - CENTER
) / FS * 1000

INFERENCE_MS = 120

TRACE_LINEWIDTH = 0.45

TRACE_COLOR = "black"

HEATMAP_ALPHA = 0.7

SHADE_ALPHA = 0.12

# ============================================================
# Load datasets
# ============================================================

print("Loading datasets...")

master_spike = np.load(MASTER_SPIKE)

master_control = np.load(MASTER_CONTROL)

X = np.load(EVAL_WINDOWS)

y = np.load(LABELS)

prob = np.load(PROB)

selected160 = np.load(SELECTED160)

print()

print("Master spike :", master_spike.shape)
print("Master control:", master_control.shape)
print("Evaluation :", X.shape)
print("Labels :", y.shape)
print("Selected160 :", selected160.shape)

# ============================================================
# Load segmentation model
# ============================================================

print()

print("Loading segmentation model...")

model = get_FAMED_Seg(WINDOW)

state = torch.load(
    CHECKPOINT,
    map_location="cpu"
)

model.load_state_dict(state)

model.eval()

print("Model loaded.")

# ============================================================
# Classification groups
# ============================================================

pred = (prob >= 0.5).astype(np.int32)

TP = np.where((pred == 1) & (y == 1))[0]

FP = np.where((pred == 1) & (y == 0))[0]

FN = np.where((pred == 0) & (y == 1))[0]

TN = np.where((pred == 0) & (y == 0))[0]

groups = {
    "TP": TP,
    "FP": FP,
    "FN": FN,
    "TN": TN,
}

print()

for k, v in groups.items():
    print(f"{k}: {len(v)}")


# ============================================================
# Run segmentation on all evaluation windows
# ============================================================
print("\nRunning segmentation model...")

segmentation_maps = []

with torch.no_grad():

    for i in range(len(X)):

        sample = X[i]

        sample_z = stats.zscore(sample, axis=None)

        tensor = torch.from_numpy(
            sample_z[np.newaxis, np.newaxis].astype(np.float32)
        )

        seg = (
            model(tensor)
            .sigmoid()
            .cpu()
            .numpy()[0, 0]
        )

        # Print detailed statistics only for the first sample
        if i == 0:
            print("\n========== FIRST SEGMENTATION OUTPUT ==========")
            print("Shape :", seg.shape)
            print("Min   :", seg.min())
            print("Max   :", seg.max())
            print("Mean  :", seg.mean())
            print("95%   :", np.percentile(seg, 95))
            print("99%   :", np.percentile(seg, 99))
            print("99.9% :", np.percentile(seg, 99.9))
            print("==============================================\n")

        segmentation_maps.append(seg)

        if (i + 1) % 25 == 0 or (i + 1) == len(X):
            print(f"{i+1}/{len(X)}")

segmentation_maps = np.asarray(segmentation_maps)

print("\nSegmentation maps:", segmentation_maps.shape)
print("Global min :", segmentation_maps.min())
print("Global max :", segmentation_maps.max())
print("Global mean:", segmentation_maps.mean())
print("99.9%      :", np.percentile(segmentation_maps, 99.9))

# ============================================================
# Convert prediction back to 305 channels
# ============================================================

print("\nExpanding segmentation maps to 305 channels...")

print("segmentation_maps shape:", segmentation_maps.shape)
print("selected160 shape:", selected160.shape)

# Expected:
# segmentation_maps = (252,234,1024)
# selected160 = (160,)

assert segmentation_maps.shape[1] == 234
assert len(selected160) == 160

seg305 = np.zeros(
    (
        segmentation_maps.shape[0],
        305,
        WINDOW
    ),
    dtype=np.float32
)

for i in range(segmentation_maps.shape[0]):

    # first 160 channels are the real MEG channels
    seg160 = segmentation_maps[i, :160, :]

    seg305[i, selected160, :] = seg160

print("Expanded maps:", seg305.shape)

print("seg305 max:", seg305.max())
print("seg305 min:", seg305.min())
print("99.9 percentile:", np.percentile(seg305,99.9))

# ============================================================
# Plot helper
# ============================================================

def compute_spacing(data):

    peak = np.percentile(
        np.abs(data),
        99.5
    )

    return peak * 2.2


def plot_waveforms(
    ax,
    signals,
    spacing,
    channel_step=1,
    color="black"
):

    n_channels = signals.shape[0]

    for ch in range(0, n_channels, channel_step):

        offset = (n_channels - ch - 1) * spacing

        ax.plot(
            TIME_MS,
            signals[ch] + offset,
            color=color,
            linewidth=TRACE_LINEWIDTH,
            zorder=2
        )

    ax.set_xlim(
        TIME_MS[0],
        TIME_MS[-1]
    )

    ax.set_xticks(
        np.arange(-800, 801, 200)
    )

    ax.tick_params(
        axis="y",
        left=False,
        labelleft=False
    )

    ax.set_xlabel("Time (ms)")

# ============================================================
# Heatmap overlay
# ============================================================

def overlay_heatmap(ax, seg, spacing):

    n_channels = seg.shape[0]

    extent = [
        TIME_MS[0],
        TIME_MS[-1],
        0,
        (n_channels - 1) * spacing
    ]

    mask = seg.copy()
    mask[mask < 0.05] = np.nan

    im = ax.imshow(
        mask[::-1],
        aspect="auto",
        cmap="jet",
        alpha=HEATMAP_ALPHA,
        interpolation="nearest",
        extent=extent,
        origin="lower",
        vmin=0,
        vmax=np.max(seg),
        zorder=1
    )

    return im

# ============================================================
# Gray inference window shading
# ============================================================

def add_gray_regions(ax):

    ax.axvspan(
        TIME_MS[0],
        -INFERENCE_MS/2,
        color="gray",
        alpha=SHADE_ALPHA,
        lw=0,
        zorder=0
    )

    ax.axvspan(
        INFERENCE_MS/2,
        TIME_MS[-1],
        color="gray",
        alpha=SHADE_ALPHA,
        lw=0,
        zorder=0
    )


# ============================================================
# Build mapping:
# evaluation index  ---> master waveform
# ============================================================

print("\nBuilding waveform mapping...")

spike_master_idx = np.where(y == 1)[0]
control_master_idx = np.where(y == 0)[0]

# ============================================================
# Paper-style figures
# ============================================================

print("\nCreating figures...")

for group_name, ids in groups.items():

    if len(ids) == 0:
        continue

    idx = ids[0]

    # --------------------------------------------------------
    # Recover the ORIGINAL 305-channel waveform
    # --------------------------------------------------------

    if y[idx] == 1:

        spike_id = np.where(spike_master_idx == idx)[0][0]

        raw = master_spike[spike_id]
        print(raw.shape)
        print(raw.min(), raw.max())
        print(np.max(np.abs(raw)))

    else:

        control_id = np.where(control_master_idx == idx)[0][0]

        raw = master_control[control_id]
        print(raw.shape)
        print(raw.min(), raw.max())
        print(np.max(np.abs(raw)))

    # --------------------------------------------------------
    # Corresponding segmentation map
    # --------------------------------------------------------

    seg = seg305[idx]

    spacing = compute_spacing(raw)
    print("spacing =", spacing)

    fig, axs = plt.subplots(
        1,
        2,
        figsize=(14,11),
        dpi=300,
        gridspec_kw={
            "width_ratios":[1,1],
            "wspace":0.05
        }
    )

    # ========================================================
    # LEFT
    # ========================================================

    plot_waveforms(
        axs[0],
        raw,
        spacing
    )

    add_gray_regions(axs[0])

    axs[0].set_title(
        "Ground Truth",
        fontsize=15,
        weight="bold"
    )

    axs[0].set_ylabel(
        "Magnetic Flux Density",
        fontsize=12
    )

    # ========================================================
    # RIGHT
    # ========================================================
    print(seg.min(), seg.max())
    im = overlay_heatmap(
        axs[1],
        seg,
        spacing
    )

    plot_waveforms(
        axs[1],
        raw,
        spacing
    )

    add_gray_regions(axs[1])

    axs[1].set_title(
        f"Prediction   p={prob[idx]:.3f}",
        fontsize=15,
        weight="bold"
    )

    ymax = raw.shape[0] * spacing

    axs[0].set_ylim(-spacing, ymax)
    axs[1].set_ylim(-spacing, ymax)

    for ax in axs:

        ax.spines["top"].set_visible(False)
        ax.spines["right"].set_visible(False)

        ax.tick_params(labelsize=10)

        ax.set_xlim(
            TIME_MS[0],
            TIME_MS[-1]
        )

        ax.set_xticks(
            np.arange(-800,801,200)
        )

    # ========================================================
    # Channel labels (paper style)
    # ========================================================

    yticks = []
    ylabels = []

    channel_step = 10      # every 10th channel

    for ch in range(0,305,channel_step):

        ypos = (305-ch-1)*spacing

        yticks.append(ypos)

        ylabels.append(str(ch+1))

    axs[0].set_yticks(yticks)
    axs[0].set_yticklabels(
        ylabels,
        fontsize=7
    )

    axs[1].set_yticks(yticks)
    axs[1].set_yticklabels([])

    # ========================================================
    # Colorbar
    # ========================================================

    cbar = fig.colorbar(
        im,
        ax=axs[1],
        fraction=0.045,
        pad=0.02
    )

    cbar.set_label(
        "Confidence",
        fontsize=11
    )

    cbar.ax.tick_params(
        labelsize=9
    )

    # ========================================================
    # Figure title
    # ========================================================

    if y[idx] == 1:

        title = (
            f"{group_name}"
            "\n"
            "(spike time ± 853 ms)"
        )

    else:

        title = (
            f"{group_name}"
            "\n"
            "(control)"
        )

    fig.suptitle(
        title,
        fontsize=16,
        fontweight="bold"
    )

    # ========================================================
    # Tight layout
    # ========================================================

    plt.subplots_adjust(
        left=0.08,
        right=0.92,
        bottom=0.08,
        top=0.90,
        wspace=0.05
    )

    # --------------------------------------------------------
    # Common x-axis
    # --------------------------------------------------------

    axs[0].set_xlabel("Time (ms)", fontsize=11)
    axs[1].set_xlabel("Time (ms)", fontsize=11)

    axs[0].set_xlim(TIME_MS[0], TIME_MS[-1])
    axs[1].set_xlim(TIME_MS[0], TIME_MS[-1])

    xticks = np.arange(-800, 801, 200)

    axs[0].set_xticks(xticks)
    axs[1].set_xticks(xticks)

    # --------------------------------------------------------
    # Remove y tick marks
    # --------------------------------------------------------

    axs[0].tick_params(axis="y", length=0)
    axs[1].tick_params(axis="y", length=0)

    # --------------------------------------------------------
    # Colorbar
    # --------------------------------------------------------

    cbar = fig.colorbar(
        im,
        ax=axs[1],
        fraction=0.046,
        pad=0.03
    )

    cbar.set_label(
        "Confidence Value",
        fontsize=11
    )

    cbar.ax.tick_params(labelsize=9)

    # --------------------------------------------------------
    # Overall title
    # --------------------------------------------------------

    if group_name == "TP":
        title = "True Positive"

    elif group_name == "FP":
        title = "False Positive"

    elif group_name == "FN":
        title = "False Negative"

    else:
        title = "True Negative"

    fig.suptitle(
        title,
        fontsize=16,
        fontweight="bold",
        y=0.97
    )

    # --------------------------------------------------------
    # Layout
    # --------------------------------------------------------

    plt.subplots_adjust(
        left=0.08,
        right=0.92,
        bottom=0.08,
        top=0.92,
        wspace=0.08
    )

    # --------------------------------------------------------
    # Save figure
    # --------------------------------------------------------

    outfile = os.path.abspath(
        os.path.join(
            OUTPUT_DIR,
            f"{group_name}.png"
        )
    )
    print(outfile)
    print(os.path.abspath(outfile))
    print(os.path.exists(os.path.dirname(outfile)))
    plt.savefig(
        outfile,
        dpi=300,
        bbox_inches="tight",
        facecolor="white"
    )

    plt.close(fig)

    print(f"Saved: {outfile}")

# ============================================================
# Finish
# ============================================================

print("\n===================================")
print("Visualization completed.")
print("===================================")
print(f"Output folder : {OUTPUT_DIR}")
print(f"Figures saved : {len(groups)}")
print("Done.")