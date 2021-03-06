USE [ProdReports]
GO
/****** Object:  StoredProcedure [dbo].[GPG_SetKPIPulseData]    Script Date: 04/30/2015 14:27:55 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROC [dbo].[GPG_SetKPIPulseData] @CurrentQuarterBegin DateTime = '4/1/2015'

AS

Declare @AsOfBookingDate DateTime, @YTD DateTime,@AsOfBookingDateKey Int, @YTDKey Int, @QTD DateTime, @QTDKey Int,@lyQRTDateBegin DateTime, @lyQRTDateBeginKey Int,@lyQRTDateEnd DateTime, @lyQRTDateEndKey Int,@Run int
Select Top 1 @AsOfBookingDate = AsOfBookingDate,@YTD = '1/1/'+CONVERT(Varchar(4),Year(AsOfBookingDate)),
    @QTD= dbo.GetQtrBegin(AsOfBookingDate),
    @lyQRTDateEnd = DateAdd(d,-1,DateAdd(m,-12,DateAdd(QUARTER,1,dbo.GetQtrBegin(AsOfBookingDate)))) ,
    @lyQRTDateBegin =DateAdd(m,-12,dbo.GetQtrBegin(AsOfBookingDate))
    From PlanDb.dbo.PlanActualAffiliationGPG
    
IF(@AsOfBookingDate<= DateAdd(d,-1,DateAdd(QUARTER,1,dbo.GetQtrBegin(@CurrentQuarterBegin))))
BEGIN

-- Drop temp tables if exist
IF OBJECT_ID('tempdb..#ParentChainBySuperRegion') IS NOT NULL
   DROP TABLE #ParentChainBySuperRegion    
   
    SELECT DISTINCT SuperRegionID, ParentChainID, RegionID
    INTO #ParentChainBySuperRegion
    FROM [CHCXSSATECH014].SSATOOLS.dbo.KPI_GPGAccountAssignments 
    
--Get Plan
IF OBJECT_ID('tempdb..#Plan') IS NOT NULL
   DROP TABLE #Plan
SELECT
p.SuperRegionID,
a.RegionID,
p.ParentChainID,
SUM(CASE Coalesce(QTDCYPLANRMD,0) WHEN 0 THEN Coalesce(QTDCYACTUALRMD,0) ELSE Coalesce(QTDCYPLANRMD,0) END) As QTDPlanRMD,
SUM(Coalesce(QTDCYACTUALRMD,0)) As QTDCyActualRMD,
SUM(CASE Coalesce(QTDCyPlanNRN,0) WHEN 0 THEN Coalesce(QTDCyActualNRN,0) ELSE Coalesce(QTDCyPlanNRN,0) END) As QTDPlanNRN,
SUM(Coalesce(QTDCyActualNRN,0)) As QTDCyActualNRN,
SUM(Coalesce(QTDLyACTUALRMD,0)) As QTDLyActualRMD,
SUM(Coalesce(QTDLYACTUALNRN,0)) As QTDLyActualNRN

INTO #Plan

FROM PlanDb.dbo.PlanActualAffiliationGPG pc
JOIN  (SELECT DISTINCT Property_Regn_ID RegionID, Property_Super_Regn_ID SuperRegionID, Property_Parnt_Chain_ID ParentChainID 
            FROM vMirror.DB2_DM.LODG_PROPERTY_DIM WHERE Property_Parnt_Chain_Acct_Typ_ID IN (1,2,3) ) p
ON pc.RegionID = p.RegionID AND pc.ParentChainID = p.ParentChainID
JOIN #ParentChainBySuperRegion a 
ON p.ParentChainID = a.ParentChainID AND p.SuperRegionID = a.SuperRegionID AND a.RegionID = CASE a.RegionID WHEN 0 THEN a.RegionID ELSE p.RegionID END
GROUP BY 
p.SuperRegionID,
a.RegionID,
p.ParentChainID

--Get Acquisitions
--Actuals
IF OBJECT_ID('tempdb..#AcqActuals') IS NOT NULL
   DROP TABLE #AcqActuals
SELECT
dhe.SuperRegionID,
dhe.ParentChainID,
SUM(RMD_CTD_Total) Acquisitions_Actual,
COUNT(Distinct a.ExpediaID) AcquiredHotelsCnt
INTO #AcqActuals
FROM Acquisition.dbo.AcqReport_ProdDetails_R4QHotel_Final a
JOIN vMirror.GPCMASTER.DimHotelExpand dhe
on a.Hotelkey = dhe.HotelKey
WHERE AcqYear = 2015
GROUP BY 
dhe.SuperRegionID,
dhe.ParentChainID

--Targets
IF OBJECT_ID('tempdb..#AcqTargets') IS NOT NULL
   DROP TABLE #AcqTargets
SELECT DISTINCT
p.SuperRegionID,
p.ParentChainID,
Acquisition_Override Acquisitions_Targets
INTO #AcqTargets
FROM [CHCXSSATECH014].SSATOOLS.dbo.KPI_GPGAccountAcqTargets t
JOIN  #ParentChainBySuperRegion     p
ON t.SuperRegionID = p.SuperRegionID AND t.ParentChainID = p.ParentChainID
/*GROUP BY 
p.SuperRegionID,
p.ParentChainID*/

--Get BML Scores

--Get BML Actuals
Declare @BMLMDX Varchar(4000), @BMLSQL Varchar(4000)

IF OBJECT_ID('tempdb..#BML') IS NOT NULL
DROP TABLE #BML
CREATE TABLE #BML(SuperRegionID Varchar(50),RegionID Varchar(50),ParentChainID Varchar(50),InvD float,BMLD float,InvN float, BMLN float)

SET @BMLMDX ='
SELECT * FROM OPENQUERY(EDWCubes_LODGBML,''
WITH 
MEMBER Measures.InvD AS [Measures].[Avail D Score]
MEMBER Measures.BMLD AS [Measures].[Rate D Score]
MEMBER Measures.InvN AS [Measures].[Avail Lose N Score]
MEMBER Measures.BMLN AS [Measures].[Rate Lose N Score]

SELECT
{
Measures.InvD,
Measures.BMLD,
Measures.InvN,
Measures.BMLN
} on columns,
(
[Hotel].[Super Region ID].[Super Region ID],
[Hotel].[Region ID].[Region ID],
[Hotel].[Parent Chain ID].[Parent Chain ID]
) on rows

/*FROM ( 
        SELECT (
                EXCEPT(
                    {([Hotel].[Parent Chain ID].[All].Children,[Comp Site].[Comp Site Name].[All].Children)},
                    {(
                        {[Hotel].[Parent Chain ID].&[-14],[Hotel].[Parent Chain ID].&[-16],[Hotel].[Parent Chain ID].&[2074]},
                    
                        { 
                        [Comp Site].[Comp Site Name].&[Wingate Inns (WG)], 
                        [Comp Site].[Comp Site Name].&[Travelodge.com (TL)], 
                        [Comp Site].[Comp Site Name].&[Super 8 Motels (SE)], 
                        [Comp Site].[Comp Site Name].&[Ramada International (RAINT)], 
                        [Comp Site].[Comp Site Name].&[Ramada Hotels (RA)], 
                        [Comp Site].[Comp Site Name].&[Knights Inn (KG)], 
                        [Comp Site].[Comp Site Name].&[Howard Johnson (HJ)], 
                        [Comp Site].[Comp Site Name].&[Extended StayAmerica (EA)], 
                        [Comp Site].[Comp Site Name].&[Disneyland Resort (DISNEYLAND)], 
                        [Comp Site].[Comp Site Name].&[Disney World Resort (DISNEY_RESORT)], 
                        [Comp Site].[Comp Site Name].&[Disney - Aulani Hawaii Resort (AULANI)], 
                        [Comp Site].[Comp Site Name].&[Days Inn (DI)], 
                        [Comp Site].[Comp Site Name].&[BaymontInn (AE)]}
                    )}
                )
        ) ON COLUMNS*/
                     
    FROM [BML - Lodging]--)

WHERE 

({
[Shop Type].[Shop Type By Category].[Shop Type Category].&[1], --default
[Shop Type].[Shop Type By Category].[Shop Type Category].&[4],-- sameday
[Shop Type].[Shop Type By Category].[Shop Type Category].&[8]-- mobile
},
[Ref Site].[Ref Site Group].[Ref Site Group Name].&[Expedia],
[Comp Site].[Is Expedia Site Group].&[No],
([Shopped Date].[Shopped Date].[Date].['+Convert(varchar(10),@QTD,120)+']:[Shopped Date].[Shopped Date].[Date].['+Convert(varchar(10),@AsOfBookingDate,120)+'])
)
'')'

INSERT INTO #BML
EXEC(@BMLMDX)

DELETE FROM #BML WHERE ParentChainID ='Null Hotel Keys' OR SuperRegionID ='Null Hotel Keys'

IF OBJECT_ID('tempdb..#BMLActuals') IS NOT NULL
   DROP TABLE #BMLActuals
SELECT 
p.SuperRegionID,
p.ParentChainID,
p.RegionID,
SUM(CONVERT(FLOAT,a.BMLD)) BMLD,
SUM(CONVERT(FLOAT,a.BMLN)) BMLN,
SUM(CONVERT(FLOAT,a.InvD)) InvD,
SUM(CONVERT(FLOAT,a.InvN)) InvN
INTO #BMLActuals
FROM #BML a
JOIN  #ParentChainBySuperRegion     p
ON a.SuperRegionID = p.SuperRegionID AND a.ParentChainID = p.ParentChainID AND p.RegionID = CASE WHEN p.RegionID = 0 THEN p.RegionID ELSE a.RegionID END
GROUP BY 
p.SuperRegionID,
p.ParentChainID,
p.RegionID

--BML Targets
IF OBJECT_ID('tempdb..#BMLTargets') IS NOT NULL
   DROP TABLE #BMLTargets
SELECT 
p.SuperRegionID,
p.ParentChainID,
RateLose_Override RateLose_Targets,
InvLose_Override InvLose_Targets
INTO #BMLTargets
FROM [CHCXSSATECH014].SSATOOLS.dbo.KPI_GPGAccountTargets t
JOIN  #ParentChainBySuperRegion     p
ON t.SuperRegionID = p.SuperRegionID AND t.ParentChainID = p.ParentChainID
/*GROUP BY 
p.SuperRegionID,
p.ParentChainID*/


TRUNCATE TABLE [dbo].[GPG_KPIPulseData] -- SELECT * FROM [dbo].[GPG_KPIPulseData] where parentchainid =17
INSERT INTO [dbo].[GPG_KPIPulseData]
SELECT DISTINCT
pc.SuperRegionID,
pc.RegionID,
pc.ParentChainID,
@AsOfBookingDate AS AsOfBookingDate,
ISNULL(p.QTDCyActualNRN,0) QTDCyActualNRN,
ISNULL(p.QTDCyActualRMD,0) QTDCyActualRMD,
ISNULL(p.QTDPlanNRN,0) QTDPlanNRN,
ISNULL(p.QTDPlanRMD,0) QTDPlanRMD,
ISNULL(Acquisitions_Targets,0) AS Acquisitions_Targets,
ISNULL(Acquisitions_Actual,0) Acquisitions_Actual,
ISNULL(bt.RateLose_Targets,0) AS RateLose_Targets,
ISNULL(bt.InvLose_Targets,0) AS InvLose_Targets,
ISNULL(ba.InvN,0) AS InvN_Actual,
ISNULL(ba.BMLN,0) AS BMLN_Actual,
ISNULL(ba.InvD,0) AS InvD_Actual,
ISNULL(ba.BMLD,0) AS BMLD_Actual,
ISNULL(QTDLyActualRMD,0) AS QTDLyActualRMD,
ISNULL(QTDLyActualNRN,0) AS QTDLyActualNRN

FROM  #ParentChainBySuperRegion    pc
LEFT JOIN #Plan p ON pc.ParentChainID = p.ParentChainID AND pc.SuperRegionID = p.SuperRegionID AND pc.RegionID = p.RegionID
LEFT JOIN #AcqActuals a ON pc.ParentChainID = a.ParentChainID AND pc.SuperRegionID = a.SuperRegionID
LEFT JOIN #AcqTargets at ON at.ParentChainID = pc.ParentChainID AND at.SuperRegionID = pc.SuperRegionID
LEFT JOIN  #BMLTargets bt ON pc.ParentChainID = bt.ParentChainID AND pc.SuperRegionID = bt.SuperRegionID
LEFT JOIN #BMLActuals ba ON pc.ParentChainID = CONVERT(INT,ba.ParentChainID) AND pc.SuperRegionID = CONVERT(INT,ba.SuperRegionID) AND pc.RegionID = CONVERT(INT,ba.RegionID)

update [dbo].[GPG_KPIPulseData]
set 
InvD_Actual = abs(InvD_Actual) ,
BMLD_Actual= abs(BMLD_Actual),
InvN_Actual = abs(InvN_Actual),
BMLN_Actual = abs(BMLN_Actual),
RateLose_Targets = abs(RateLose_Targets) ,
InvLose_Targets = abs(InvLose_Targets)

END
