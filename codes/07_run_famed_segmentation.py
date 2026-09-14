import numpy as np
import torch
from scipy import stats

from Model.FAMED_model import get_FAMED_Seg

# --------------------------------------------------
# Load evaluation dataset
# --------------------------------------------------

X = np.load(r"bch001_test\evaluation_windows.npy")
y = np.load(r"bch001_test\evaluation_labels.npy")

print("Evaluation windows:", X.shape)

# --------------------------------------------------
# Load pretrained segmentation model
# --------------------------------------------------

model = get_FAMED_Seg(1024)

ckpt = torch.load(
    "../data/model_weights/FAMED/FAMED_Segmentation_Weight_Fold9.ckpt",
    map_location=torch.device("cpu"),
)

model.load_state_dict(ckpt)
model.eval()

print("Segmentation model loaded.")

# --------------------------------------------------
# Run segmentation
# --------------------------------------------------

seg_maps = []

peak_rows = []
peak_times = []
peak_scores = []

with torch.no_grad():

    for i, window in enumerate(X):

        data = stats.zscore(window, axis=None)

        x = torch.from_numpy(
            data[np.newaxis, np.newaxis].astype(np.float32)
        )

        seg = model(x).sigmoid().squeeze().cpu().numpy()

        seg_maps.append(seg)

        r, t = np.unravel_index(
            np.argmax(seg),
            seg.shape
        )

        peak_rows.append(r)
        peak_times.append(t)
        peak_scores.append(seg[r, t])

        if (i + 1) % 25 == 0:
            print(f"{i+1}/{len(X)}")

seg_maps = np.stack(seg_maps)

peak_rows = np.array(peak_rows)
peak_times = np.array(peak_times)
peak_scores = np.array(peak_scores)

# --------------------------------------------------
# Save
# --------------------------------------------------

np.save(r"bch001_test\famed_segmentation_maps.npy", seg_maps)
np.save(r"bch001_test\famed_peak_rows.npy", peak_rows)
np.save(r"bch001_test\famed_peak_times.npy", peak_times)
np.save(r"bch001_test\famed_peak_scores.npy", peak_scores)

print("\nSaved segmentation results.")

print("\nPeak score summary")
print("------------------")
print("Mean :", peak_scores.mean())
print("Median :", np.median(peak_scores))
print("Max :", peak_scores.max())
print("Min :", peak_scores.min())