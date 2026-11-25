# Smart Manufacturing: Machine Health Monitoring

Graduation project for the **Digital Egypt Pioneers Initiative (DEPI)** – Data Analyst Track.

The project takes machine sensor readings from a smart factory, builds a data warehouse (SQL Server star schema), analyzes the data, and trains a model that estimates the **health score** of every machine. A Streamlit app lets a user upload a CSV file and get a report that shows which machines need maintenance first.

## Key results

| Item | Result |
|---|---|
| Dataset | 100,000 readings, 5,000 machines, 72 columns (cleaned) |
| Final target | `machine_health_score` (0-100) |
| Model | Linear Regression (scaled numbers + one-hot encoded text), validated with `GroupKFold` by machine |
| Score | R² = 0.80, MAE = 1.87 points (baseline MAE = 4.15) |
| LightGBM (comparison) | R² = 0.80, MAE = 1.88 (same performance, so the simpler model was chosen) |
| Predicting if a machine fails | Not possible with this dataset (every approach equals random guessing) |

Failures are rare (1.47%) and the experiments in the notebook (sections 4 to 9) show that they do not depend on the sensor readings, so the app ranks machines by predicted health instead of giving a failure probability.

## Repository structure

```
Manufacturing_Analysis/
├── Data/
│   ├── Raw_Data/                  # original dataset
│   └── Cleaned_Data/              # dataset after cleaning (used by the model)
├── Data Modeling & ERD/           # ERD image and draw.io file
├── Star Schema & SQL Queries/     # star schema image and SQL queries
├── docs/
│   └── PROJECT_DOCUMENTATION.md   # full project documentation (team template)
├── .streamlit/
│   └── config.toml                # app theme
├── Manufacturing_Analysis.ipynb   # data warehouse, EDA, and machine learning
├── app.py                         # Streamlit app
├── model.joblib                   # trained model (created by the notebook)
├── sample_upload.csv              # small demo file for the app
├── requirements.txt
└── README.md
```

## Tech stack

Python, pandas, scikit-learn (Linear Regression), LightGBM (experiments), Plotly, Streamlit, SQL Server (SQLAlchemy), Jupyter Notebook.

## System requirements

- Python 3.10 or newer
- 4 GB RAM or more
- Windows, macOS, or Linux
- Only for the SQL Server part of the notebook: SQL Server, **ODBC Driver 17 for SQL Server**, and `pip install pyodbc` (it is not in `requirements.txt` because the machine learning section and the app do not need it)

## Installation

```bash
git clone <repository-url>
cd Manufacturing_Analysis

python -m venv .venv
.venv\Scripts\activate          # Windows
# source .venv/bin/activate     # macOS / Linux

pip install -r requirements.txt
```

## Configuration

- **SQL Server:** the connection settings (server, database, driver) are in the notebook, in the cell that creates the SQL engine (`SQL_SERVER`, `SQL_DATBASE`, `SQL_DRIVER`). Change them to match your machine.
- **Data path:** the machine learning section reads the cleaned data from `Data/Cleaned_Data/`. Make sure the file name in the notebook matches the file in this folder.
- **App theme:** `.streamlit/config.toml` (the folder name must be exactly `.streamlit`).

## How to run

### 1. Notebook
Open `Manufacturing_Analysis.ipynb` and run the cells from top to bottom.
The machine learning section starts at **Machine Learning Modeling**. It only needs the cleaned data file, so it can run without SQL Server. At the end it saves `model.joblib`.

### 2. Streamlit app
```bash
streamlit run app.py
```
Open the address shown in the terminal (usually http://localhost:8501).

## Using the app

1. Upload a CSV or Parquet file with the same columns as the cleaned dataset (or click **Try with demo data**).
2. See the fleet status, the machines that need attention first, and the weakest part of each machine.
3. Filter by factory, machine type, or status.
4. Download the report (HTML) or the table (CSV).

**Status levels** are based on the machines used to train the model: the weakest 10% are *Needs attention*, the next 20% are *Monitor*, and the rest are *Healthy*.

## Limitations

- The dataset looks synthetic: failures are random and the health columns are almost constant for each machine. The model estimates the long-term health of a machine, not sudden changes.
- The app ranks machines by health. It does not predict when a machine will fail.

## Documentation

See [`docs/PROJECT_DOCUMENTATION.md`](docs/PROJECT_DOCUMENTATION.md).

## Team

| Name | Role |
|---|---|
| _TBD_ | _TBD_ |
