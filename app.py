# Machine Health Report - Streamlit app
# Run with:  streamlit run app.py
# It loads the model that was trained and saved in the notebook (model.joblib).

import datetime
import os
import joblib
import numpy as np
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
from plotly.subplots import make_subplots
import streamlit as st

st.set_page_config(page_title="Machine Health Report", page_icon="🏭", layout="wide")

# ------------------------------------------------------------------ settings
RED, ORANGE, GREEN, BLUE = "#E5484D", "#F5A524", "#2FB67C", "#3B82F6"
STATUS_COLORS = {"Needs attention": RED, "Monitor": ORANGE, "Healthy": GREEN}
STATUS_ICONS = {"Needs attention": "🔴 Needs attention", "Monitor": "🟠 Monitor", "Healthy": "🟢 Healthy"}
STATUS_ORDER = ["Needs attention", "Monitor", "Healthy"]

# Same column groups as in the notebook (these columns are not used by the model)
id_cols = ['monitoring_id', 'machine_id', 'timestamp', 'date_stamp', 'time_stamp', 'last_maintenance_date']
leak_cols = ['failure_type', 'remaining_useful_life_hours', 'machine_failure']
health_cols = ['bearing_health', 'motor_health', 'pump_health',
               'hydraulic_health', 'electrical_health', 'cooling_system_health']
anomaly_cols = ['temperature_anomaly_score', 'vibration_anomaly_score', 'pressure_anomaly_score',
                'electrical_anomaly_score', 'energy_anomaly_score']
derived_cols = health_cols + anomaly_cols + ['machine_health_score']

PART_NAMES = {
    'bearing_health': 'Bearings', 'motor_health': 'Motor', 'pump_health': 'Pump',
    'hydraulic_health': 'Hydraulic system', 'electrical_health': 'Electrical system',
    'cooling_system_health': 'Cooling system'}

st.markdown("""
<style>
.block-container {padding-top: 2rem;}
div[data-testid="stMetric"] {background: #F4F6FA; border-radius: 12px; padding: 14px 18px;}
div[data-testid="stMetricLabel"] p {font-size: 0.9rem; color: #5B6678;}
</style>
""", unsafe_allow_html=True)


# ------------------------------------------------------------------ model
@st.cache_resource(show_spinner='Loading the model (first run can take a few seconds)...')
def load_model():
    return joblib.load('model.joblib')


def predict_health(data, model_info):
    """Predict the health score (0-100) of every reading in the uploaded file."""
    X = data.drop(columns=id_cols + leak_cols + derived_cols + ['model'], errors='ignore')

    missing = [col for col in model_info['features'] if col not in X.columns]
    if missing:
        raise ValueError('The file is missing these columns: ' + ', '.join(missing[:10]))

    # The model also prepares the data (scaling and encoding), so we only pass the right columns
    return model_info['model'].predict(X[model_info['features']])


# ------------------------------------------------------------------ table of machines
def number_from(text):
    """'FAC-03' -> 3, 'MCH-00441' -> 441. Used to show friendly names."""
    digits = ''.join(ch for ch in str(text) if ch.isdigit())
    return int(digits) if digits else None


def make_machine_table(data, thresholds):
    """One row per machine: average predicted health, status and weakest part."""
    columns = {'predicted_health': 'mean'}
    for col in ['machine_type', 'factory_id', 'production_line', 'machine_age'] + health_cols:
        if col in data.columns:
            columns[col] = 'first' if col in ['machine_type', 'factory_id', 'production_line', 'machine_age'] else 'mean'
    grouped = data.groupby('machine_id').agg(columns)
    grouped['readings'] = data.groupby('machine_id').size()
    grouped = grouped.reset_index()

    table = pd.DataFrame()
    table['machine_id'] = grouped['machine_id']
    kind = grouped['machine_type'] if 'machine_type' in grouped else 'Machine'
    table['Machine'] = kind.astype(str) + ' #' + grouped['machine_id'].map(number_from).astype(str)
    table['Type'] = kind if 'machine_type' in grouped else 'Machine'
    if 'factory_id' in grouped:
        table['Factory'] = 'Factory ' + grouped['factory_id'].map(number_from).astype(str)
    if 'production_line' in grouped:
        table['Line'] = 'Line ' + grouped['production_line'].map(number_from).astype(str)
    if 'machine_age' in grouped:
        table['Age (years)'] = grouped['machine_age']
    table['Health score'] = grouped['predicted_health'].round(1)

    table['Status'] = np.where(table['Health score'] <= thresholds['attention'], 'Needs attention',
                      np.where(table['Health score'] <= thresholds['monitor'], 'Monitor', 'Healthy'))

    if all(col in grouped.columns for col in health_cols):
        table['Weakest part'] = grouped[health_cols].idxmin(axis=1).map(PART_NAMES)
    table['Readings'] = grouped['readings']
    return table.sort_values('Health score').reset_index(drop=True)


# ------------------------------------------------------------------ charts
def style(fig, height=380):
    fig.update_layout(height=height, margin=dict(l=10, r=10, t=50, b=10),
                      paper_bgcolor='rgba(0,0,0,0)', plot_bgcolor='rgba(0,0,0,0)',
                      title_font_size=16, font_family='sans-serif')
    return fig


def chart_status(table):
    counts = table['Status'].value_counts().reindex(STATUS_ORDER).fillna(0)
    fig = go.Figure(go.Pie(labels=counts.index, values=counts.values, hole=0.62, sort=False,
                           marker_colors=[STATUS_COLORS[s] for s in counts.index],
                           textinfo='value', hovertemplate='%{label}: %{value} machines<extra></extra>'))
    fig.update_layout(title='Fleet status', legend=dict(orientation='h', y=-0.05))
    fig.add_annotation(text=f'<b>{len(table)}</b><br>machines', showarrow=False, font_size=16)
    return style(fig)


def chart_ranking(table, thresholds, top_n):
    """Dot plot of the least healthy machines, with colored zones for each status."""
    shown = table.head(top_n)
    low = max(0, shown['Health score'].min() - 3)
    high = min(100, max(shown['Health score'].max(), thresholds['monitor']) + 3)

    fig = go.Figure()
    fig.add_vrect(x0=low, x1=thresholds['attention'], fillcolor=RED, opacity=0.10, line_width=0)
    fig.add_vrect(x0=thresholds['attention'], x1=thresholds['monitor'], fillcolor=ORANGE, opacity=0.12, line_width=0)
    fig.add_vrect(x0=thresholds['monitor'], x1=high, fillcolor=GREEN, opacity=0.10, line_width=0)
    fig.add_trace(go.Scatter(
        x=shown['Health score'], y=shown['Machine'], mode='markers',
        marker=dict(size=13, color=[STATUS_COLORS[s] for s in shown['Status']], line=dict(width=1, color='white')),
        hovertemplate='%{y}<br>Health score: %{x}<extra></extra>'))
    fig.update_yaxes(autorange='reversed', title=None)
    fig.update_xaxes(range=[low, high], title='Health score (higher is better)')
    fig.update_layout(title=f'The {len(shown)} machines that need attention first', showlegend=False)
    return style(fig, height=max(380, 26 * len(shown) + 120))


def chart_by_group(table, group, group_label):
    """Stacked bars: how many machines are in each status, for every factory / type / line."""
    counts = table.groupby([group, 'Status']).size().reset_index(name='Machines')
    names = sorted(table[group].unique(), key=lambda n: (number_from(n) or 0, str(n)))
    fig = px.bar(counts, x='Machines', y=group, color='Status', orientation='h',
                 color_discrete_map=STATUS_COLORS, category_orders={'Status': STATUS_ORDER})
    fig.update_yaxes(categoryorder='array', categoryarray=names, autorange='reversed', title=None)
    fig.update_xaxes(title='Number of machines')
    fig.update_layout(title=f'Machine status by {group_label}', legend=dict(orientation='h', y=-0.2, title=None))
    return style(fig, height=max(320, 40 * len(names) + 140))


def chart_weak_parts(table):
    weak = table[table['Status'] != 'Healthy']['Weakest part'].value_counts().sort_values()
    fig = go.Figure(go.Bar(x=weak.values, y=weak.index, orientation='h', marker_color=BLUE,
                           hovertemplate='%{y}: %{x} machines<extra></extra>'))
    fig.update_layout(title='Weakest part in machines that need attention or monitoring')
    fig.update_xaxes(title='Number of machines')
    return style(fig, height=max(300, 50 * len(weak) + 120))


def chart_distribution(table, thresholds):
    fig = px.histogram(table, x='Health score', nbins=30, color_discrete_sequence=[BLUE])
    fig.add_vline(x=thresholds['attention'], line_dash='dash', line_color=RED)
    fig.add_vline(x=thresholds['monitor'], line_dash='dash', line_color=ORANGE)
    fig.update_layout(title='Distribution of machine health', bargap=0.05)
    fig.update_xaxes(title='Health score')
    fig.update_yaxes(title='Number of machines')
    return style(fig)


def chart_gauge(score, thresholds, color):
    fig = go.Figure(go.Indicator(
        mode='gauge+number', value=score, number=dict(font=dict(size=44, color=color)),
        gauge=dict(axis=dict(range=[40, 100]), bar=dict(color='#334155', thickness=0.25),
                   steps=[dict(range=[40, thresholds['attention']], color='#F4A3A6'),
                          dict(range=[thresholds['attention'], thresholds['monitor']], color='#F8D28A'),
                          dict(range=[thresholds['monitor'], 100], color='#A6E0C5')])))
    return style(fig, height=250)


def chart_sensors(machine_data):
    sensors = [('temperature_c', 'Temperature (°C)'), ('vibration_mm_s', 'Vibration (mm/s)'),
               ('pressure_bar', 'Pressure (bar)'), ('motor_temperature_c', 'Motor temperature (°C)')]
    sensors = [s for s in sensors if s[0] in machine_data.columns]
    x = machine_data['timestamp'] if 'timestamp' in machine_data.columns else np.arange(len(machine_data))
    fig = make_subplots(rows=2, cols=2, subplot_titles=[s[1] for s in sensors])
    for i, (col, name) in enumerate(sensors):
        fig.add_trace(go.Scatter(x=x, y=machine_data[col], mode='lines+markers', line_color=BLUE, name=name),
                      row=i // 2 + 1, col=i % 2 + 1)
    fig.update_layout(showlegend=False, title='Recent sensor readings')
    return style(fig, height=480)


# ------------------------------------------------------------------ report file
def build_report(table, thresholds, figures):
    """A single HTML file the user can save, print or email."""
    attention = table[table['Status'] == 'Needs attention']
    columns = [c for c in ['Machine', 'Factory', 'Line', 'Health score', 'Weakest part'] if c in attention.columns]

    html = ['<html><head><meta charset="utf-8"><title>Machine Health Report</title>',
            '<style>body{font-family:Arial,sans-serif;max-width:1000px;margin:30px auto;color:#1B2430}',
            'table{border-collapse:collapse;width:100%}th,td{border-bottom:1px solid #ddd;padding:8px;text-align:left}',
            '.kpis{display:flex;gap:16px}.kpi{background:#F4F6FA;border-radius:10px;padding:14px;flex:1}',
            '.kpi b{font-size:26px;display:block}</style></head><body>',
            '<h1>Machine Health Report</h1>',
            f'<p>Generated on {datetime.date.today():%d %B %Y}</p>',
            '<div class="kpis">',
            f'<div class="kpi">Machines<b>{len(table)}</b></div>',
            f'<div class="kpi">Average health<b>{table["Health score"].mean():.1f}</b></div>',
            f'<div class="kpi">Need attention<b>{(table["Status"] == "Needs attention").sum()}</b></div>',
            f'<div class="kpi">Monitor<b>{(table["Status"] == "Monitor").sum()}</b></div></div>']
    for i, fig in enumerate(figures):
        html.append(fig.to_html(full_html=False, include_plotlyjs=(i == 0)))
    html.append('<h2>Machines that need attention</h2>')
    html.append(attention[columns].to_html(index=False) if len(attention) else '<p>No machines need attention.</p>')
    html.append('</body></html>')
    return '\n'.join(html)


# ================================================================== page
model_info = load_model()
thresholds = model_info['thresholds']

st.title('🏭 Machine Health Report')
st.caption('Upload your machine readings (CSV or Parquet) to see the health of each machine and which ones need maintenance first.')

uploaded = st.file_uploader('Upload readings file', type=['csv', 'parquet'])
use_demo = st.session_state.get('use_demo', False)

if uploaded is None and not use_demo:
    st.info('Upload a file with the same columns as the cleaned machine dataset.')
    if os.path.exists('sample_upload.csv') and st.button('Try with demo data'):
        st.session_state['use_demo'] = True
        st.rerun()
    st.stop()

if uploaded is not None:
    data = pd.read_parquet(uploaded) if uploaded.name.endswith('.parquet') else pd.read_csv(uploaded)
else:
    data = pd.read_csv('sample_upload.csv')
    st.caption('Showing demo data.')

try:
    data['predicted_health'] = predict_health(data, model_info)
except ValueError as error:
    st.error(str(error))
    st.stop()

if 'timestamp' in data.columns:
    data['timestamp'] = pd.to_datetime(data['timestamp'], errors='coerce')

all_machines = make_machine_table(data, thresholds)

# ---------------------------------------------------------------- filters
st.sidebar.header('Filters')
view = all_machines
if 'Factory' in view.columns:
    chosen = st.sidebar.multiselect('Factory', sorted(view['Factory'].unique(), key=lambda s: number_from(s) or 0))
    view = view[view['Factory'].isin(chosen)] if chosen else view
if 'Type' in view.columns:
    chosen = st.sidebar.multiselect('Machine type', sorted(view['Type'].unique()))
    view = view[view['Type'].isin(chosen)] if chosen else view
chosen = st.sidebar.multiselect('Status', STATUS_ORDER)
view = view[view['Status'].isin(chosen)] if chosen else view
view = view.reset_index(drop=True)

if view.empty:
    st.warning('No machines match the selected filters.')
    st.stop()

# ---------------------------------------------------------------- summary
c1, c2, c3, c4 = st.columns(4)
c1.metric('Machines', len(view))
c2.metric('Average health', f"{view['Health score'].mean():.1f} / 100")
c3.metric('Need attention', int((view['Status'] == 'Needs attention').sum()))
c4.metric('Monitor', int((view['Status'] == 'Monitor').sum()))

with st.expander('How is the status decided?'):
    st.write(
        'The health score (0-100) is estimated from the sensor readings of each machine. '
        f'Machines are compared with the machines used to train the model: a score of **{thresholds["attention"]} or lower** '
        f'is *Needs attention* (the weakest 10%), **up to {thresholds["monitor"]}** is *Monitor* (the next 20%), '
        'and anything higher is *Healthy*.')

# ---------------------------------------------------------------- charts
left, right = st.columns([1, 2])
fig_status = chart_status(view)
left.plotly_chart(fig_status, width='stretch')
top_n = right.slider('Machines to show', 5, min(40, len(view)), min(15, len(view))) if len(view) > 5 else len(view)
fig_rank = chart_ranking(view, thresholds, top_n)
right.plotly_chart(fig_rank, width='stretch')

figures = [fig_status, fig_rank]
left, right = st.columns(2)
group_names = {'Factory': 'factory', 'Type': 'machine type', 'Line': 'production line'}
group_options = [g for g in group_names if g in view.columns and view[g].nunique() > 1]
if group_options:
    group = left.radio('Compare by', group_options, horizontal=True, format_func=lambda g: group_names[g].capitalize())
    fig_group = chart_by_group(view, group, group_names[group])
    left.plotly_chart(fig_group, width='stretch')
    figures.append(fig_group)
else:
    left.plotly_chart(chart_distribution(view, thresholds), width='stretch')
if 'Weakest part' in view.columns and (view['Status'] != 'Healthy').any():
    fig_weak = chart_weak_parts(view)
    right.plotly_chart(fig_weak, width='stretch')
    figures.append(fig_weak)

# ---------------------------------------------------------------- table
st.subheader('All machines')
show = view.drop(columns=['machine_id', 'Type'], errors='ignore').copy()
show['Status'] = show['Status'].map(STATUS_ICONS)
st.dataframe(show, width='stretch', hide_index=True,
             column_config={'Health score': st.column_config.ProgressColumn('Health score', min_value=0, max_value=100, format='%.1f')})

d1, d2 = st.columns(2)
d1.download_button('⬇️ Download report (HTML)', build_report(view, thresholds, figures).encode(),
                   'machine_health_report.html', 'text/html')
d2.download_button('⬇️ Download table (CSV)', show.to_csv(index=False).encode(), 'machine_health_table.csv', 'text/csv')

# ---------------------------------------------------------------- one machine
st.subheader('Machine details')
name = st.selectbox('Choose a machine', view['Machine'].tolist())
row = view[view['Machine'] == name].iloc[0]
machine_data = data[data['machine_id'] == row['machine_id']]
if 'timestamp' in machine_data.columns:
    machine_data = machine_data.sort_values('timestamp')

g1, g2 = st.columns([1, 2])
g1.plotly_chart(chart_gauge(row['Health score'], thresholds, STATUS_COLORS[row['Status']]), width='stretch')
g1.markdown(f"**Status:** {STATUS_ICONS[row['Status']]}")
for col in ['Factory', 'Line', 'Age (years)', 'Weakest part']:
    if col in row.index:
        g1.markdown(f"**{col}:** {row[col]}")

part = row['Weakest part'] if 'Weakest part' in row.index else 'the main components'
if row['Status'] == 'Needs attention':
    g2.error(f'Plan maintenance soon. Check the **{part}** first.')
elif row['Status'] == 'Monitor':
    g2.warning(f'Keep an eye on this machine and inspect the **{part}** at the next service.')
else:
    g2.success('This machine is healthy. No action needed.')
g2.plotly_chart(chart_sensors(machine_data), width='stretch')
