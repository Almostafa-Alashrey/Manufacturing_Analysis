CREATE TABLE [Dim_Date] (
  [date_key] int PRIMARY KEY,
  [full_date] date,
  [year] int,
  [quarter] int,
  [month_name] varchar(20),
  [month] int,
  [day_name] varchar(20),
  [day] int,
  [day_of_year] int,
  [week_of_year] int,
  [is_weekend] bit
)
GO

CREATE TABLE [Dim_Shift] (
  [shift_key] int PRIMARY KEY,
  [shift] varchar(20),
  [shift_name] varchar(20)
)
GO

CREATE TABLE [Dim_Machine] (
  [machine_key] int PRIMARY KEY,
  [machine_id] varchar(10)
)
GO

CREATE TABLE [Dim_Operator] (
  [operator_key] int PRIMARY KEY,
  [operator_id] varchar(10)
)
GO

CREATE TABLE [Dim_Product] (
  [product_key] int PRIMARY KEY,
  [product_id] varchar(10)
)
GO

CREATE TABLE [Dim_Quality] (
  [quality_key] int PRIMARY KEY,
  [type] char(1),
  [product_quality] varchar(10)
)
GO

CREATE TABLE [Dim_Downtime_Reason] (
  [downtime_reason_key] int PRIMARY KEY,
  [downtime_reason] varchar(50)
)
GO

CREATE TABLE [Dim_Defect_Type] (
  [defect_type_key] int PRIMARY KEY,
  [defect_type] varchar(50)
)
GO

CREATE TABLE [Fact_Production] (
  [date_key] int NOT NULL,
  [shift_key] int NOT NULL,
  [machine_key] int NOT NULL,
  [operator_key] int NOT NULL,
  [product_key] int NOT NULL,
  [quality_key] int NOT NULL,
  [downtime_reason_key] int NOT NULL,
  [defect_type_key] int NOT NULL,
  [planned_time_min] int,
  [downtime_min] int,
  [total_units] int,
  [good_units] int,
  [reject_units] int,
  [energy_kwh] decimal(10,2),
  [air_temperature_k] decimal(6,1),
  [process_temperature_k] decimal(6,1),
  [rotational_speed_rpm] int,
  [torque_nm] decimal(6,2),
  [tool_wear_min] int,
  [machine_failure] bit,
  PRIMARY KEY ([date_key], [shift_key], [machine_key])
)
GO

ALTER TABLE [Fact_Production] ADD FOREIGN KEY ([date_key]) REFERENCES [Dim_Date] ([date_key])
GO

ALTER TABLE [Fact_Production] ADD FOREIGN KEY ([shift_key]) REFERENCES [Dim_Shift] ([shift_key])
GO

ALTER TABLE [Fact_Production] ADD FOREIGN KEY ([machine_key]) REFERENCES [Dim_Machine] ([machine_key])
GO

ALTER TABLE [Fact_Production] ADD FOREIGN KEY ([operator_key]) REFERENCES [Dim_Operator] ([operator_key])
GO

ALTER TABLE [Fact_Production] ADD FOREIGN KEY ([product_key]) REFERENCES [Dim_Product] ([product_key])
GO

ALTER TABLE [Fact_Production] ADD FOREIGN KEY ([quality_key]) REFERENCES [Dim_Quality] ([quality_key])
GO

ALTER TABLE [Fact_Production] ADD FOREIGN KEY ([downtime_reason_key]) REFERENCES [Dim_Downtime_Reason] ([downtime_reason_key])
GO

ALTER TABLE [Fact_Production] ADD FOREIGN KEY ([defect_type_key]) REFERENCES [Dim_Defect_Type] ([defect_type_key])
GO
