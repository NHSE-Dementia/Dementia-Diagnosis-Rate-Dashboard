   /****** Script for reformatting Dementia Record and Rate Data and then calculating pbar, nbar, UCL, LCL for pchart ******/

 --Produces temporary table for Sub ICB and Region data and will delete any previous table named that
IF OBJECT_ID ('[NHSE_Sandbox_MentalHealth].[dbo].TEMP_SubICBtoRegion') IS NOT NULL DROP TABLE [NHSE_Sandbox_MentalHealth].[dbo].TEMP_SubICBtoRegion
--This table provides the latest Sub ICB Codes (which currently are the same as 2021 CCG Codes) and provides the Sub ICB Name, ICB and Region names and codes for that Sub ICB code
--It contains 106 rows for the 106 Sub ICBs
SELECT DISTINCT 
	[Organisation_Code] AS 'Sub ICB Code'
	,[Organisation_Name] AS 'Sub ICB Name' 
    ,[STP_Code] AS 'ICB Code'
	,[STP_Name] AS 'ICB Name'
	,[Region_Code] AS 'Region Code' 
	,[Region_Name] AS 'Region Name'
--INTO creates this table
INTO [NHSE_Sandbox_MentalHealth].[dbo].TEMP_SubICBtoRegion
FROM [NHSE_Reference].[dbo].[tbl_Ref_ODS_Commissioner_Hierarchies]
--Effective_To has the date the Org Code is applicable to so the codes currently in use have null in this column.
--Filtering for just clinical commissioning group org type - this means commissioning hubs are excluded
WHERE [Effective_To] IS NULL AND [NHSE_Organisation_Type]='CLINICAL COMMISSIONING GROUP'


--Combines the two data collections into one place

IF OBJECT_ID ('[NHSE_Sandbox_MentalHealth].[dbo].TEMP_DEM_DDR_Base') IS NOT NULL DROP TABLE [NHSE_Sandbox_MentalHealth].[dbo].TEMP_DEM_DDR_Base

SELECT
		[Org_Type]
		,[Org_Code]
		,[Measure]
		,[Measure_Value]
		,[Effective_Snapshot_Date]
		into [NHSE_Sandbox_MentalHealth].[dbo].TEMP_DEM_DDR_Base
	FROM [NHSE_UKHF].[Rec_Dementia_Diag].[vw_Diag_Rate_By_NHS_Org_65Plus1]

INSERT INTO [NHSE_Sandbox_MentalHealth].[dbo].TEMP_DEM_DDR_Base
SELECT
	[Org_Type]
	,[Org_Code]
	,[Measure]
	,[Measure_Value]
	,[Effective_Snapshot_Date]
FROM [NHSE_UKHF].[Primary_Care_Dementia].[vw_Diag_Rate_By_NHS_Org_65Plus1]






--Deletes temporary table if it exists so it can be written into
IF OBJECT_ID ('[NHSE_Sandbox_MentalHealth].[dbo].TEMP_DEM_DDRStep1') IS NOT NULL DROP TABLE [NHSE_Sandbox_MentalHealth].[dbo].TEMP_DEM_DDRStep1
--Creates temporary table #DDRStep1 to get the data into a pivoted format and estimate, register and rates recalculated based on updated 2021 geography
SELECT *
INTO [NHSE_Sandbox_MentalHealth].[dbo].TEMP_DEM_DDRStep1
FROM(
-----------------------------------Sub ICBs (recalculated based on introduction of ICBs and sub ICBs in July 2022)----------------------------------------------------------------------------------------
SELECT
     --MAX is used on the columns which aren't included in the group by statement at the end and which don't use the sum function
    [Effective_Snapshot_Date]
	--CAST AS FLOAT used to remove the excess 0s
	--Summing the dementia estimate and register grouped by the effective snapshot date, the CCG21 code and name in order to recalculate these for any mergers/splits that have occurred
    ,SUM(CAST([DEMENTIA_ESTIMATE_65_PLUS] AS FLOAT)) AS [DEMENTIA_ESTIMATE_65_PLUS]
    ,SUM(CAST([DEMENTIA_REGISTER_65_PLUS] AS FLOAT)) AS [DEMENTIA_REGISTER_65_PLUS]
	--Recalculating the DDR for the CCG21 codes
	,(SUM([DEMENTIA_REGISTER_65_PLUS])/SUM([DEMENTIA_ESTIMATE_65_PLUS])) AS [DEMENTIA_RATE_65_PLUS]
	,'Sub ICB' AS [Org Type]
	,b.[Sub ICB Code] AS [Org Code]
    ,b.[Sub ICB Name] AS [Org Name]
	,MAX(b.[ICB Name]) AS [ICB Name]
	,null AS [Region Name]
	
FROM
    --For pivoting the UKHF DDR data:
	(SELECT
		[Org_Type]
		,[Org_Code]
		,[Measure]
		,[Measure_Value]
		,[Effective_Snapshot_Date]
	FROM [NHSE_Sandbox_MentalHealth].[dbo].TEMP_DEM_DDR_Base
		) AS SourceTable
		PIVOT(
		--Have to use an aggregate function for pivot to work so use max to work around this
		MAX([Measure_Value])
		FOR [Measure] IN ([DEMENTIA_ESTIMATE_65_PLUS], [DEMENTIA_REGISTER_65_PLUS])
		) AS PivotTable
		--Pivot section end
--Joins to the CCG lookup table to match the old CCG codes with the 2021 codes. 
LEFT JOIN [NHSE_Sandbox_MentalHealth].[dbo].[CCG_2020_Lookup] a ON Org_Code= a.IC_CCG COLLATE DATABASE_DEFAULT
--Joins to the CCGtoRegionSBG temp table which has the CCG21 codes, CCG names and matches to STP codes, STP names and Region codes and Region names
LEFT JOIN [NHSE_Sandbox_MentalHealth].[dbo].TEMP_SubICBtoRegion b ON a.CCG21 = b.[Sub ICB Code]
--Only join on CCGs - the UKHF data has all geography types in the column Org_Type i.e. Region, STP, CCG and we only want CCG
WHERE Org_Type='CCG' or Org_Type='SUB_ICB_LOC'
--This relates to the summing of register and estimate to recalculate these based on CCG21 code and name and the effective snapshot date
GROUP BY [Sub ICB Code], [Sub ICB Name], [Effective_Snapshot_Date]
--Add this table to the next one for STPs (will match column names and then just add the new rows for STPs below)

UNION
---------------------------------------------------------------------ICBs (recalculated based on Sub ICB 2021 codes)---------------------------------------------------------------------
SELECT
     --MAX is used on the columns which aren't included in the group by statement at the end and which don't use the sum function
    [Effective_Snapshot_Date]
	--CAST AS FLOAT used to remove the excess 0s
	--Summing the dementia estimate and register grouped by the effective snapshot date, the CCG21 code and name in order to recalculate these for any mergers/splits that have occurred
    ,SUM(CAST([DEMENTIA_ESTIMATE_65_PLUS] AS FLOAT)) AS [DEMENTIA_ESTIMATE_65_PLUS]
    ,SUM(CAST([DEMENTIA_REGISTER_65_PLUS] AS FLOAT)) AS [DEMENTIA_REGISTER_65_PLUS]
	--Recalculating the DDR for the CCG21 codes
	,(SUM([DEMENTIA_REGISTER_65_PLUS])/SUM([DEMENTIA_ESTIMATE_65_PLUS])) AS [DEMENTIA_RATE_65_PLUS]
	,'ICB' AS [Org Type]
	,b.[ICB Code] AS [Org Code]
    ,b.[ICB Name] AS [Org Name]
	,b.[ICB Name]
	,MAX(b.[Region Name]) AS [Region Name]
FROM
    --For pivoting the UKHF DDR data:
	(SELECT
		[Org_Type]
		,[Org_Code]
		,[Measure]
		,[Measure_Value]
		,[Effective_Snapshot_Date]
	FROM [NHSE_Sandbox_MentalHealth].[dbo].TEMP_DEM_DDR_Base
		) AS SourceTable
		PIVOT(
		--Have to use an aggregate function for pivot to work so use max to work around this
		MAX([Measure_Value])
		FOR [Measure] IN ([DEMENTIA_ESTIMATE_65_PLUS], [DEMENTIA_REGISTER_65_PLUS])
		) AS PivotTable
		--Pivot section end
--Joins to the CCG lookup table to match the old CCG codes with the 2021 codes. 
--The datatypes didn't match as UKHF data doesn't accept nulls and the lookup table does so collate database_default changes that to allow the join
LEFT JOIN [NHSE_Sandbox_MentalHealth].[dbo].[CCG_2020_Lookup] a ON Org_Code= a.IC_CCG COLLATE DATABASE_DEFAULT
--Joins to the CCGtoRegionSBG temp table which has the CCG21 codes, CCG names and matches to STP codes, STP names and Region codes and Region names
LEFT JOIN [NHSE_Sandbox_MentalHealth].[dbo].TEMP_SubICBtoRegion b ON a.CCG21 = b.[Sub ICB Code]
--Only join on CCGs - the UKHF data has all geography types in the column Org_Type i.e. Region, STP, CCG and we only want CCG
WHERE Org_Type='CCG' or Org_Type='SUB_ICB_LOC'
--This relates to the summing of register and estimate to recalculate these based on CCG21 code and name and the effective snapshot date
GROUP BY [ICB Code], [ICB Name], [Effective_Snapshot_Date]

--Add this table to the next one for Regions (will match column names and then just add the new rows for Regions below)
UNION
----------------------------------------------------------------------------Regions (recalculated based on CCG21 codes)-------------------------------------------------------------------------------------
SELECT
     --MAX is used on the columns which aren't included in the group by statement at the end and which don't use the sum function
    [Effective_Snapshot_Date]
	--CAST AS FLOAT used to remove the excess 0s
	--Summing the dementia estimate and register grouped by the effective snapshot date, the CCG21 code and name in order to recalculate these for any mergers/splits that have occurred
    ,SUM(CAST([DEMENTIA_ESTIMATE_65_PLUS] AS FLOAT)) AS [DEMENTIA_ESTIMATE_65_PLUS]
    ,SUM(CAST([DEMENTIA_REGISTER_65_PLUS] AS FLOAT)) AS [DEMENTIA_REGISTER_65_PLUS]
	--Recalculating the DDR for the CCG21 codes
	,(SUM([DEMENTIA_REGISTER_65_PLUS])/SUM([DEMENTIA_ESTIMATE_65_PLUS])) AS [DEMENTIA_RATE_65_PLUS]
	,'Region' AS [Org Type]
	,b.[Region Code] AS [Org Code]
    ,b.[Region Name] AS [Org Name]
	,null AS [ICB Name]
	,b.[Region Name]
FROM
    --For pivoting the UKHF DDR data:
	(SELECT
		[Org_Type]
		,[Org_Code]
		,[Measure]
		,[Measure_Value]
		,[Effective_Snapshot_Date]
	FROM [NHSE_Sandbox_MentalHealth].[dbo].TEMP_DEM_DDR_Base
		) AS SourceTable
		PIVOT(
		--Have to use an aggregate function for pivot to work so use max to work around this
		MAX([Measure_Value])
		FOR [Measure] IN ([DEMENTIA_ESTIMATE_65_PLUS], [DEMENTIA_REGISTER_65_PLUS])
		) AS PivotTable
		--Pivot section end
--Joins to the CCG lookup table to match the old CCG codes with the 2021 codes. 
--The datatypes didn't match as UKHF data doesn't accept nulls and the lookup table does so collate database_default changes that to allow the join
LEFT JOIN [NHSE_Sandbox_MentalHealth].[dbo].[CCG_2020_Lookup] a ON Org_Code= a.IC_CCG COLLATE DATABASE_DEFAULT
--Joins to the CCGtoRegionSBG temp table which has the CCG21 codes, CCG names and matches to STP codes, STP names and Region codes and Region names
LEFT JOIN [NHSE_Sandbox_MentalHealth].[dbo].TEMP_SubICBtoRegion b ON a.CCG21 = b.[Sub ICB Code] 
--Only join on CCGs - the UKHF data has all geography types in the column Org_Type i.e. Region, STP, CCG and we only want CCG
WHERE Org_Type='CCG' or Org_Type='SUB_ICB_LOC'
--This relates to the summing of register and estimate to recalculate these based on CCG21 code and name and the effective snapshot date
GROUP BY [Region Code], [Region Name], [Effective_Snapshot_Date]

--Add this table to the next one for National (will match column names and then just add the new rows for National below)
UNION
----------------------------------------------National (just filtered for what has been reported for England in UKHF data as shouldn't be impacted by CCG mergers etc)----------------------------------------

SELECT
     --MAX is used on the columns which aren't included in the group by statement at the end and which don't use the sum function
    [Effective_Snapshot_Date]
	--CAST AS FLOAT used to remove the excess 0s
	--Summing the dementia estimate and register grouped by the effective snapshot date, the CCG21 code and name in order to recalculate these for any mergers/splits that have occurred
    ,SUM(CAST([DEMENTIA_ESTIMATE_65_PLUS] AS FLOAT)) AS [DEMENTIA_ESTIMATE_65_PLUS]
    ,SUM(CAST([DEMENTIA_REGISTER_65_PLUS] AS FLOAT)) AS [DEMENTIA_REGISTER_65_PLUS]
	--Recalculating the DDR for the CCG21 codes
	,(SUM([DEMENTIA_REGISTER_65_PLUS])/SUM([DEMENTIA_ESTIMATE_65_PLUS])) AS [DEMENTIA_RATE_65_PLUS]
	,'National' AS [Org Type]
	,'England'AS [Org Code]
    ,'England' AS [Org Name]
	,null AS [STP Name]
	,null AS [Region Name]
FROM
    --For pivoting the UKHF DDR data:
	(SELECT
		[Org_Type]
		,[Org_Code]
		,[Measure]
		,[Measure_Value]
		,[Effective_Snapshot_Date]
	FROM [NHSE_Sandbox_MentalHealth].[dbo].TEMP_DEM_DDR_Base
		) AS SourceTable
		PIVOT(
		--Have to use an aggregate function for pivot to work so use max to work around this
		MAX([Measure_Value])
		FOR [Measure] IN ([DEMENTIA_ESTIMATE_65_PLUS], [DEMENTIA_REGISTER_65_PLUS])
		) AS PivotTable
		--Pivot section end

WHERE Org_Type='COUNTRY_RESPONSIBILITY' 
--This relates to the summing of register and estimate to recalculate these based on CCG21 code and name and the effective snapshot date
GROUP BY [Effective_Snapshot_Date]
)_

-----------------------------
IF OBJECT_ID ('[NHSE_Sandbox_MentalHealth].[dbo].TEMP_DEM_DDRStep2') IS NOT NULL DROP TABLE [NHSE_Sandbox_MentalHealth].[dbo].TEMP_DEM_DDRStep2
--Creates temporary table #DDRStep2 to calculate the pbar, UCL, LCL for the full time period (as opposed to pre and post covid as calculated below)
--These calculated columns will be referred to as pbar2, UCL2, LCL2 to distinguish from the pre and post covid versions
SELECT *
INTO [NHSE_Sandbox_MentalHealth].[dbo].TEMP_DEM_DDRStep2
FROM(

SELECT
	MAX(b.[Org Type]) AS [Org Type]
	,MAX(b.[Org Name]) AS [Org Name]
	,b.[Org Code]
	,MAX(b.[ICB Name]) AS [ICB Name]
	,MAX(b.[Region Name]) AS [Region Name]
	,MAX([pbar2]) AS [pbar2]
	--,MAX([nbar2]) AS [nbar2]
	,MAX([pbar2]+(3*SQRT([pbar2]*(1-[pbar2])/[DEMENTIA_ESTIMATE_65_PLUS]))) AS [UCL2]
	,MAX([pbar2]-(3*SQRT([pbar2]*(1-[pbar2])/[DEMENTIA_ESTIMATE_65_PLUS]))) AS [LCL2]
	,a.[Effective_Snapshot_Date]
	,MAX(a.[DEMENTIA_ESTIMATE_65_PLUS]) AS [DEMENTIA_ESTIMATE_65_PLUS]
	,MAX(a.[DEMENTIA_REGISTER_65_PLUS]) AS [DEMENTIA_REGISTER_65_PLUS]
	,MAX(a.[DEMENTIA_RATE_65_PLUS]) AS [DEMENTIA_RATE_65_PLUS]
FROM(
SELECT
	MAX([Org Type]) AS [Org Type]
	,MAX([Org Name]) AS [Org Name]
	,[Org Code]
	,MAX([ICB Name]) AS [ICB Name]
	,MAX([Region Name]) AS [Region Name]
	--,(SUM([DEMENTIA_REGISTER_65_PLUS])/COUNT([Effective_Snapshot_Date]))AS [nbar2]
	,SUM([DEMENTIA_REGISTER_65_PLUS])/SUM([DEMENTIA_ESTIMATE_65_PLUS]) AS [pbar2]
FROM [NHSE_Sandbox_MentalHealth].[dbo].TEMP_DEM_DDRStep1
GROUP BY [Org Code]) AS b
LEFT JOIN [NHSE_Sandbox_MentalHealth].[dbo].TEMP_DEM_DDRStep1 a ON b.[Org Code] = a.[Org Code]
GROUP BY b.[Org Code], a.[Effective_Snapshot_Date]
)_

--This final query will write into the Dementia_Diagnosis_Rate_Dashboard table. It will delete the existing table so it can write in the table
--This final query is for calculating the pbar, UCL, LCL for before and after the start of Covid (March 2020)
IF OBJECT_ID ('[NHSE_Sandbox_MentalHealth].[dbo].[Dementia_Diagnosis_Rate_Dashboard_V2]') IS NOT NULL DROP TABLE [NHSE_Sandbox_MentalHealth].[dbo].[Dementia_Diagnosis_Rate_Dashboard_V2]
SELECT *
INTO [NHSE_Sandbox_MentalHealth].[dbo].[Dementia_Diagnosis_Rate_Dashboard_V2]
FROM(
-----------------------------------------------------------------------Pre Covid ---------------------------------------------------------------
SELECT
	MAX(x.[Org Type]) AS [Org Type]
	,MAX(x.[Org Name]) AS [Org Name]
	,x.[Org Code]
	,MAX(x.[ICB Name]) AS [ICB Name]
	,MAX(x.[Region Name]) AS [Region Name]
	,MAX(x.[pbar]) AS [pbar]
	--,MAX([nbar]) AS [nbar]
	,MAX([pbar]+(3*SQRT([pbar]*(1-[pbar])/[DEMENTIA_ESTIMATE_65_PLUS]))) AS [UCL]
	,MAX([pbar]-(3*SQRT([pbar]*(1-[pbar])/[DEMENTIA_ESTIMATE_65_PLUS]))) AS [LCL]
	,y.[Effective_Snapshot_Date]
	,MAX(y.[DEMENTIA_ESTIMATE_65_PLUS]) AS [DEMENTIA_ESTIMATE_65_PLUS]
	,MAX(y.[DEMENTIA_REGISTER_65_PLUS]) AS [DEMENTIA_REGISTER_65_PLUS]
	,MAX(y.[DEMENTIA_RATE_65_PLUS]) AS [DEMENTIA_RATE_65_PLUS]
	,MAX(y.[pbar2]) AS [pbar2]
	,MAX(y.[UCL2]) AS [UCL2]
	,MAX(y.[LCL2]) AS [LCL2]
FROM(
SELECT
	MAX([Org Type]) AS [Org Type]
	,MAX([Org Name]) AS [Org Name]
	,[Org Code]
	,MAX([ICB Name]) AS [ICB Name]
	,MAX([Region Name]) AS [Region Name]
	--,(SUM([DEMENTIA_REGISTER_65_PLUS])/COUNT([Effective_Snapshot_Date]))AS [nbar]
	,SUM([DEMENTIA_REGISTER_65_PLUS])/SUM([DEMENTIA_ESTIMATE_65_PLUS]) AS [pbar]
FROM [NHSE_Sandbox_MentalHealth].[dbo].TEMP_DEM_DDRStep1
WHERE [Effective_Snapshot_Date]<'2020-03-01'
GROUP BY [Org Code]) AS x
LEFT JOIN [NHSE_Sandbox_MentalHealth].[dbo].TEMP_DEM_DDRStep2 y ON x.[Org Code] = y.[Org Code]
WHERE [Effective_Snapshot_Date]<'2020-03-01'
GROUP BY x.[Org Code], y.[Effective_Snapshot_Date]


UNION

-----------------------------------------------------------------------Post March 2020 ---------------------------------------------------------------

SELECT
	MAX(x.[Org Type]) AS [Org Type]
	,MAX(x.[Org Name]) AS [Org Name]
	,x.[Org Code]
	,MAX(x.[ICB Name]) AS [ICB Name]
	,MAX(x.[Region Name]) AS [Region Name]
	,MAX(x.[pbar]) AS [pbar]
	--,MAX([nbar]) AS [nbar]
	,MAX([pbar]+(3*SQRT([pbar]*(1-[pbar])/[DEMENTIA_ESTIMATE_65_PLUS]))) AS [UCL]
	,MAX([pbar]-(3*SQRT([pbar]*(1-[pbar])/[DEMENTIA_ESTIMATE_65_PLUS]))) AS [LCL]
	,y.[Effective_Snapshot_Date]
	,MAX(y.[DEMENTIA_ESTIMATE_65_PLUS]) AS [DEMENTIA_ESTIMATE_65_PLUS]
	,MAX(y.[DEMENTIA_REGISTER_65_PLUS]) AS [DEMENTIA_REGISTER_65_PLUS]
	,MAX(y.[DEMENTIA_RATE_65_PLUS]) AS [DEMENTIA_RATE_65_PLUS]
	,MAX(y.[pbar2]) AS [pbar2]
	,MAX(y.[UCL2]) AS [UCL2]
	,MAX(y.[LCL2]) AS [LCL2]
FROM(
SELECT
	MAX([Org Type]) AS [Org Type]
	,MAX([Org Name]) AS [Org Name]
	,[Org Code]
	,MAX([ICB Name]) AS [ICB Name]
	,MAX([Region Name]) AS [Region Name]
	--,(SUM([DEMENTIA_REGISTER_65_PLUS])/COUNT([Effective_Snapshot_Date]))AS [nbar]
	,SUM([DEMENTIA_REGISTER_65_PLUS])/SUM([DEMENTIA_ESTIMATE_65_PLUS]) AS [pbar]
FROM [NHSE_Sandbox_MentalHealth].[dbo].TEMP_DEM_DDRStep1
WHERE [Effective_Snapshot_Date]>'2020-03-01'
GROUP BY [Org Code]) AS x
LEFT JOIN [NHSE_Sandbox_MentalHealth].[dbo].TEMP_DEM_DDRStep2 y ON x.[Org Code] = y.[Org Code]
WHERE [Effective_Snapshot_Date]>'2020-03-01'
GROUP BY x.[Org Code], y.[Effective_Snapshot_Date]
)_


DROP TABLE [NHSE_Sandbox_MentalHealth].[dbo].TEMP_SubICBtoRegion
DROP TABLE [NHSE_Sandbox_MentalHealth].[dbo].TEMP_DEM_DDRStep1
DROP TABLE [NHSE_Sandbox_MentalHealth].[dbo].TEMP_DEM_DDRStep2
DROP TABLE [NHSE_Sandbox_MentalHealth].[dbo].TEMP_DEM_DDR_Base