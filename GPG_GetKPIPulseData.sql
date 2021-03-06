USE [ProdReports]
GO
/****** Object:  StoredProcedure [dbo].[GPG_GetKPIPulseData]    Script Date: 04/30/2015 14:29:00 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER Proc [dbo].[GPG_GetKPIPulseData] --[dbo].[GPG_GetKPIPulseData_TEST] '2'
@SuperRegions varchar(4000) = Null,
@Chains varchar(4000) =Null

AS
--DECLARE 
--@SuperRegions varchar(4000) ,
--@Chains varchar(4000)

--SELECT @SuperRegions = Null,@Chains =Null

CREATE TABLE #GlobalParentChainBySuperRegion (SuperRegionID int, SuperRegionName varchar(200),RegionID int,ParentChainID int,ParentChainName varchar(200),PROPERTY_PARNT_CHAIN_ACCT_TYP_ID int)
CREATE TABLE #FilteredParentChainBySuperRegion (SuperRegionID int,SuperRegionName varchar(200),RegionID int, ParentChainID int,ParentChainName varchar(200),PROPERTY_PARNT_CHAIN_ACCT_TYP_ID int)

SELECT * INTO #KPI_GPGAccountAssignments FROM [CHCXSSATECH014].SSATOOLS.dbo.KPI_GPGAccountAssignments 

SELECT * INTO #IncludeInTotal FROM #KPI_GPGAccountAssignments WHERE IncludeInTotal = 1

SELECT * INTO #KPI_GPGResource FROM [CHCXSSATECH014].SSATOOLS.dbo.KPI_GPGResource

SELECT * INTO #KPI_GPGTeams FROM [CHCXSSATECH014].SSATOOLS.dbo.KPI_GPGTeams

INSERT INTO  #GlobalParentChainBySuperRegion (SuperRegionID,SuperRegionName,RegionID,ParentChainID,ParentChainName,PROPERTY_PARNT_CHAIN_ACCT_TYP_ID) -- pulls all available ParentChains & SuperRegions
SELECT DISTINCT a.SuperRegionID, pc.SuperRegionName, a.RegionID,a.ParentChainID, pc.ParentChainName,PROPERTY_PARNT_CHAIN_ACCT_TYP_ID 
       FROM #KPI_GPGAccountAssignments a --
        JOIN (SELECT DISTINCT Property_Super_Regn_ID SuperRegionID, Property_Super_Regn_Name SuperRegionName,Property_Parnt_Chain_ID ParentChainID, PROPERTY_PARNT_CHAIN_NAME ParentChainName, PROPERTY_PARNT_CHAIN_ACCT_TYP_ID 
					FROM vMirror.DB2_DM.LODG_PROPERTY_DIM WHERE Property_Super_Regn_ID >0 AND PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2) ) pc
        ON pc.ParentChainID = a.ParentChainID AND pc.SuperRegionID = a.SuperRegionID 
                        

IF(ISNULL(@Chains,'')='') -- if no Chains provided
    BEGIN
        IF(ISNULL(@SuperRegions,'')='') -- if no SuperRegions provided
            BEGIN
                INSERT INTO  #FilteredParentChainBySuperRegion (SuperRegionID,SuperRegionName,RegionID,ParentChainID,ParentChainName,PROPERTY_PARNT_CHAIN_ACCT_TYP_ID) -- pulls all available ParentChains & SuperRegions
                SELECT SuperRegionID,SuperRegionName,RegionID,ParentChainID,ParentChainName,PROPERTY_PARNT_CHAIN_ACCT_TYP_ID FROM #GlobalParentChainBySuperRegion
            END
        ELSE -- there's SuperRegion value
            BEGIN
                INSERT INTO  #FilteredParentChainBySuperRegion (SuperRegionID,SuperRegionName,RegionID,ParentChainID,ParentChainName, PROPERTY_PARNT_CHAIN_ACCT_TYP_ID) -- pulls all available Parentchains for selected SuperRegion(s)
                SELECT pc.* FROM #GlobalParentChainBySuperRegion  pc
                        JOIN(SELECT [str] AS SuperRegionID FROM dbo.charlist_to_table(@SuperRegions,DEFAULT)) sr ON pc.SuperRegionID = sr.SuperRegionID
                        
            END
    END
    ELSE -- if there're Chains provided
        IF(ISNULL(@SuperRegions,'')='') -- if no SuperRegions provided
            BEGIN
                INSERT INTO  #FilteredParentChainBySuperRegion (SuperRegionID,SuperRegionName,RegionID,ParentChainID,ParentChainName, PROPERTY_PARNT_CHAIN_ACCT_TYP_ID) -- pulls all available SuperRegions for selected ParentChain(s)
                SELECT pc.* FROM #GlobalParentChainBySuperRegion  pc
                        JOIN(SELECT [str] AS ParentChainID FROM dbo.charlist_to_table(@Chains,DEFAULT)) ps ON ps.ParentChainID = pc.ParentChainID  
         
            END
        ELSE -- there's SuperRegion value
            BEGIN
                INSERT INTO  #FilteredParentChainBySuperRegion (SuperRegionID,SuperRegionName,RegionID,ParentChainID,ParentChainName, PROPERTY_PARNT_CHAIN_ACCT_TYP_ID)
                SELECT pc.* FROM #GlobalParentChainBySuperRegion pc
                        JOIN(SELECT [str] AS ParentChainID FROM dbo.charlist_to_table(@Chains,DEFAULT)) ps ON ps.ParentChainID = pc.ParentChainID
                        JOIN(SELECT [str] AS SuperRegionID FROM dbo.charlist_to_table(@SuperRegions,DEFAULT)) sr ON sr.SuperRegionID = pc.SuperRegionID
                        WHERE Property_Parnt_Chain_Acct_Typ_ID >0
            END
            
-- Total
SELECT 
0 RoleID
,'Total GPG' ResourceName
,pc.*
,[AsOfBookingDate]
,[QTDCyActualNRN]
,[QTDCyActualRMD]
,ISNULL([QTDPlanNRN],0) [QTDPlanNRN]
,ISNULL([QTDPlanRMD],0) [QTDPlanRMD]
,[QTDLyActualNRN]
,[QTDLyActualRMD]
,ISNULL(Acquisitions_Targets,0) Acquisitions_Targets
,ISNULL(Acquisitions_Actual,0) Acquisitions_Actual
,ISNULL(CASE WHEN PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2,3) THEN RateLose_Targets ELSE 0 END,0) RateLose_Targets
,ISNULL(CASE WHEN PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2,3) THEN InvLose_Targets ELSE 0 END,0) InvLose_Targets
,ISNULL(CASE WHEN PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2,3) THEN [InvD_Actual] ELSE 0 END,0) [InvD_Actual]
,ISNULL(CASE WHEN PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2,3) THEN [BMLD_Actual] ELSE 0 END,0) [BMLD_Actual]
,ISNULL(CASE WHEN PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2,3) THEN [InvN_Actual] ELSE 0 END,0) [InvN_Actual]
,ISNULL(CASE WHEN PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2,3) THEN [BMLN_Actual] ELSE 0 END,0) [BMLN_Actual]
,a.IncludeInTotal

FROM #GlobalParentChainBySuperRegion pc
JOIN #KPI_GPGAccountAssignments a
ON pc.ParentChainID = a.ParentChainID AND pc.SuperRegionID = a.SuperRegionID AND pc.RegionID = a.RegionID
JOIN [dbo].[GPG_KPIPulseData] k
ON pc.ParentChainID = k.ParentChainID AND pc.SuperRegionID = k.SuperRegionID AND pc.RegionID = k.RegionID
WHERE a.IncludeInTotal = 1

UNION ALL

--Gaming Team into the total
SELECT 
0 RoleID
,'Total GPG' ResourceName
,SuperRegionID,SuperRegionName,RegionID,ParentChainID,ParentChainName,PROPERTY_PARNT_CHAIN_ACCT_TYP_ID
,[AsOfBookingDate]
,SUM([QTDCyActualNRN])
,SUM([QTDCyActualRMD])
,SUM([QTDPlanNRN]) [QTDPlanNRN]
,SUM([QTDPlanRMD]) [QTDPlanRMD]
,SUM([QTDLyActualNRN])
,SUM([QTDLyActualRMD])
,SUM(ISNULL(k.tAcq,0)) Acquisitions_Targets
,SUM(ISNULL(k.aAcq,0)) Acquisitions_Actual
,ISNULL(CASE WHEN SUM(k.tRateD) <> 0 THEN SUM(k.tRateN)/SUM(k.tRateD) END,0)*100 RateLose_Targets
,ISNULL(CASE WHEN SUM(k.tAvailD) <> 0 THEN SUM(k.tAvailN)/SUM(k.tAvailD) END,0)*100 InvLose_Targets
,SUM(ISNULL(k.aAvailD,0)) [InvD_Actual]
,SUM(ISNULL(k.aRateD,0)) [BMLD_Actual]
,SUM(ISNULL(k.aAvailN,0)) [InvN_Actual]
,SUM(ISNULL(k.aRateN,0)) [BMLN_Actual]
,1 IncludeInTotal
FROM [dbo].[KPIPulseData] k
JOIN (SELECT DISTINCT MarketID,SuperRegionID,SuperRegionName,RegionID,0 ParentchainID,'Gaming' ParentChainName,3 PROPERTY_PARNT_CHAIN_ACCT_TYP_ID FROM [vSIP_Hierarchy ] WHERE RegionID = 85494) m
ON k.MarketID = m.MarketID
GROUP BY SuperRegionID,SuperRegionName,RegionID,ParentChainID,ParentChainName,PROPERTY_PARNT_CHAIN_ACCT_TYP_ID,AsOfBookingDate

UNION ALL

--Team   
SELECT 
1 RoleID
,ISNULL(t.TeamName,'Unassigned') ResourceName
,pc.*
,[AsOfBookingDate]
,[QTDCyActualNRN]
,[QTDCyActualRMD]
,CASE WHEN ISNULL([QTDPlanNRN],0)=0 THEN [QTDCyActualNRN] ELSE [QTDPlanNRN] END [QTDPlanNRN]
,CASE WHEN ISNULL([QTDPlanRMD],0)=0 THEN [QTDCyActualRMD] ELSE [QTDPlanRMD] END [QTDPlanRMD]
,[QTDLyActualNRN]
,[QTDLyActualRMD]
,ISNULL(Acquisitions_Targets,0) Acquisitions_Targets
,ISNULL(Acquisitions_Actual,0) Acquisitions_Actual
,ISNULL(CASE WHEN PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2,3) THEN RateLose_Targets ELSE 0 END,0) RateLose_Targets
,ISNULL(CASE WHEN PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2,3) THEN InvLose_Targets ELSE 0 END,0) InvLose_Targets
,ISNULL(CASE WHEN PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2,3) THEN [InvD_Actual] ELSE 0 END,0) [InvD_Actual]
,ISNULL(CASE WHEN PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2,3) THEN [BMLD_Actual] ELSE 0 END,0) [BMLD_Actual]
,ISNULL(CASE WHEN PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2,3) THEN [InvN_Actual] ELSE 0 END,0) [InvN_Actual]
,ISNULL(CASE WHEN PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2,3) THEN [BMLN_Actual] ELSE 0 END,0) [BMLN_Actual]
,a.IncludeInTotal

FROM #FilteredParentChainBySuperRegion pc
JOIN #KPI_GPGAccountAssignments a
ON pc.ParentChainID = a.ParentChainID AND pc.SuperRegionID = a.SuperRegionID AND pc.RegionID = a.RegionID
LEFT JOIN [dbo].[GPG_KPIPulseData] k
ON pc.ParentChainID = k.ParentChainID AND pc.SuperRegionID = k.SuperRegionID AND k.RegionID = a.RegionID
LEFT JOIN #KPI_GPGTeams t
ON a.TeamID = t.TeamID
WHERE a.IncludeInTotal = 1

UNION ALL

--Gaming Team   
SELECT 
1 RoleID
,'Gaming' ResourceName
,SuperRegionID,SuperRegionName,m.RegionID,ParentChainID,ParentChainName,PROPERTY_PARNT_CHAIN_ACCT_TYP_ID
,[AsOfBookingDate]
,SUM([QTDCyActualNRN])
,SUM([QTDCyActualRMD])
,SUM([QTDPlanNRN]) [QTDPlanNRN]
,SUM([QTDPlanRMD]) [QTDPlanRMD]
,SUM([QTDLyActualNRN])
,SUM([QTDLyActualRMD])
,AVG(ISNULL(acq.tAcq,0)) Acquisitions_Targets
,AVG(ISNULL(acq.aAcq,0)) Acquisitions_Actual
,ISNULL(CASE WHEN SUM(k.tRateD) <> 0 THEN SUM(k.tRateN)/SUM(k.tRateD) END,0)*100 RateLose_Targets
,ISNULL(CASE WHEN SUM(k.tAvailD) <> 0 THEN SUM(k.tAvailN)/SUM(k.tAvailD) END,0)*100 InvLose_Targets
,SUM(ISNULL(k.aAvailD,0)) [InvD_Actual]
,SUM(ISNULL(k.aRateD,0)) [BMLD_Actual]
,SUM(ISNULL(k.aAvailN,0)) [InvN_Actual]
,SUM(ISNULL(k.aRateN,0)) [BMLN_Actual]
,1 IncludeInTotal
FROM [dbo].[KPIPulseData] k
JOIN (SELECT DISTINCT MarketID,SuperRegionID,SuperRegionName,RegionID,0 ParentchainID,'Gaming' ParentChainName,3 PROPERTY_PARNT_CHAIN_ACCT_TYP_ID FROM [vSIP_Hierarchy ] WHERE RegionID = 85494) m
ON k.MarketID = m.MarketID
LEFT JOIN 
(SELECT mma.RegionID,SUM(ISNULL(acq.aAcq,0)) aAcq, SUM(ISNULL(acq.tAcq,0)) tAcq 
		FROM dbo.KPIAcq acq 
		JOIN (SELECT DISTINCT RegionID,MMAID FROM [vSIP_Hierarchy ] WHERE RegionID = 85494) mma 
		ON acq.MMAID = mma.MMAID
		GROUP BY mma.RegionID) acq
ON m.RegionID = acq.RegionID

GROUP BY SuperRegionID,SuperRegionName,m.RegionID,ParentChainID,ParentChainName,PROPERTY_PARNT_CHAIN_ACCT_TYP_ID,AsOfBookingDate

UNION ALL            

-- Account Owners -- Customed only for Maxim
SELECT 
2 RoleID
,ISNULL(r.ResourceName,'Unassigned') ResourceName
,pc.*
,[AsOfBookingDate]
,[QTDCyActualNRN]
,[QTDCyActualRMD]
,CASE WHEN ISNULL([QTDPlanNRN],0)=0 THEN [QTDCyActualNRN] ELSE [QTDPlanNRN] END [QTDPlanNRN]
,CASE WHEN ISNULL([QTDPlanRMD],0)=0 THEN [QTDCyActualRMD] ELSE [QTDPlanRMD] END [QTDPlanRMD]
,[QTDLyActualNRN]
,[QTDLyActualRMD]
,ISNULL(Acquisitions_Targets,0) Acquisitions_Targets
,ISNULL(Acquisitions_Actual,0) Acquisitions_Actual
,ISNULL(CASE WHEN PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2,3) THEN RateLose_Targets ELSE 0 END,0) RateLose_Targets
,ISNULL(CASE WHEN PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2,3) THEN InvLose_Targets ELSE 0 END,0) InvLose_Targets
,ISNULL(CASE WHEN PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2,3) THEN [InvD_Actual] ELSE 0 END,0) [InvD_Actual]
,ISNULL(CASE WHEN PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2,3) THEN [BMLD_Actual] ELSE 0 END,0) [BMLD_Actual]
,ISNULL(CASE WHEN PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2,3) THEN [InvN_Actual] ELSE 0 END,0) [InvN_Actual]
,ISNULL(CASE WHEN PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2,3) THEN [BMLN_Actual] ELSE 0 END,0) [BMLN_Actual]
,a.IncludeInTotal

FROM #FilteredParentChainBySuperRegion pc
JOIN #KPI_GPGAccountAssignments a
ON pc.ParentChainID = a.ParentChainID AND pc.SuperRegionID = a.SuperRegionID AND pc.RegionID = a.RegionID
JOIN [dbo].[GPG_KPIPulseData] k
ON pc.ParentChainID = k.ParentChainID AND pc.SuperRegionID = k.SuperRegionID AND pc.RegionID = k.RegionID
JOIN #KPI_GPGResource r 
ON a.TeamLeader = r.ResourceAlias
WHERE a.TeamLeader = 'memasri' AND a.IncludeInTotal = 1

UNION ALL

-- Global Owners
SELECT 
3 RoleID
,ISNULL(r.ResourceName,'Unassigned') ResourceName
,pc.*
,[AsOfBookingDate]
,[QTDCyActualNRN]
,[QTDCyActualRMD]
,CASE WHEN ISNULL([QTDPlanNRN],0)=0 THEN [QTDCyActualNRN] ELSE [QTDPlanNRN] END [QTDPlanNRN]
,CASE WHEN ISNULL([QTDPlanRMD],0)=0 THEN [QTDCyActualRMD] ELSE [QTDPlanRMD] END [QTDPlanRMD]
,[QTDLyActualNRN]
,[QTDLyActualRMD]
,ISNULL(Acquisitions_Targets,0) Acquisitions_Targets
,ISNULL(Acquisitions_Actual,0) Acquisitions_Actual
,ISNULL(CASE WHEN PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2,3) THEN RateLose_Targets ELSE 0 END,0) RateLose_Targets
,ISNULL(CASE WHEN PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2,3) THEN InvLose_Targets ELSE 0 END,0) InvLose_Targets
,ISNULL(CASE WHEN PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2,3) THEN [InvD_Actual] ELSE 0 END,0) [InvD_Actual]
,ISNULL(CASE WHEN PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2,3) THEN [BMLD_Actual] ELSE 0 END,0) [BMLD_Actual]
,ISNULL(CASE WHEN PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2,3) THEN [InvN_Actual] ELSE 0 END,0) [InvN_Actual]
,ISNULL(CASE WHEN PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2,3) THEN [BMLN_Actual] ELSE 0 END,0) [BMLN_Actual]
,a.IncludeInTotal

FROM #FilteredParentChainBySuperRegion pc
JOIN #KPI_GPGAccountAssignments a
ON pc.ParentChainID = a.ParentChainID AND pc.SuperRegionID = a.SuperRegionID AND pc.RegionID = a.RegionID
JOIN [dbo].[GPG_KPIPulseData] k
ON pc.ParentChainID = k.ParentChainID AND pc.SuperRegionID = k.SuperRegionID AND pc.RegionID = k.RegionID
JOIN #KPI_GPGResource r
ON a.GlobalOwner = r.ResourceAlias
WHERE a.IncludeInTotal = 1

UNION ALL

--Regional Owners
SELECT 
4 RoleID
,ISNULL(r.ResourceName,'Unassigned') ResourceName
,pc.*
,[AsOfBookingDate]
,[QTDCyActualNRN]
,[QTDCyActualRMD]
,CASE WHEN ISNULL([QTDPlanNRN],0)=0 THEN [QTDCyActualNRN] ELSE [QTDPlanNRN] END [QTDPlanNRN]
,CASE WHEN ISNULL([QTDPlanRMD],0)=0 THEN [QTDCyActualRMD] ELSE [QTDPlanRMD] END [QTDPlanRMD]
,[QTDLyActualNRN]
,[QTDLyActualRMD]
,ISNULL(Acquisitions_Targets,0) Acquisitions_Targets
,ISNULL(Acquisitions_Actual,0) Acquisitions_Actual
,ISNULL(CASE WHEN PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2,3) THEN RateLose_Targets ELSE 0 END,0) RateLose_Targets
,ISNULL(CASE WHEN PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2,3) THEN InvLose_Targets ELSE 0 END,0) InvLose_Targets
,ISNULL(CASE WHEN PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2,3) THEN [InvD_Actual] ELSE 0 END,0) [InvD_Actual]
,ISNULL(CASE WHEN PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2,3) THEN [BMLD_Actual] ELSE 0 END,0) [BMLD_Actual]
,ISNULL(CASE WHEN PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2,3) THEN [InvN_Actual] ELSE 0 END,0) [InvN_Actual]
,ISNULL(CASE WHEN PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2,3) THEN [BMLN_Actual] ELSE 0 END,0) [BMLN_Actual]
,a.IncludeInTotal

FROM #FilteredParentChainBySuperRegion pc
JOIN #KPI_GPGAccountAssignments a
ON pc.ParentChainID = a.ParentChainID AND pc.SuperRegionID = a.SuperRegionID AND pc.RegionID = a.RegionID
JOIN [dbo].[GPG_KPIPulseData] k
ON pc.ParentChainID = k.ParentChainID AND pc.SuperRegionID = k.SuperRegionID AND pc.RegionID = k.RegionID
JOIN #KPI_GPGResource r
ON a.RegionalOwner = r.ResourceAlias

UNION ALL

--Lead RM    
SELECT 
5 RoleID
,ISNULL(lrm.ResourceName,'Unassigned') ResourceName
,pc.*
,[AsOfBookingDate]
,[QTDCyActualNRN]
,[QTDCyActualRMD]
,CASE WHEN ISNULL([QTDPlanNRN],0)=0 THEN [QTDCyActualNRN] ELSE [QTDPlanNRN] END [QTDPlanNRN]
,CASE WHEN ISNULL([QTDPlanRMD],0)=0 THEN [QTDCyActualRMD] ELSE [QTDPlanRMD] END [QTDPlanRMD]
,[QTDLyActualNRN]
,[QTDLyActualRMD]
,ISNULL(Acquisitions_Targets,0) Acquisitions_Targets
,ISNULL(Acquisitions_Actual,0) Acquisitions_Actual
,ISNULL(CASE WHEN PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2,3) THEN RateLose_Targets ELSE 0 END,0) RateLose_Targets
,ISNULL(CASE WHEN PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2,3) THEN InvLose_Targets ELSE 0 END,0) InvLose_Targets
,ISNULL(CASE WHEN PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2,3) THEN [InvD_Actual] ELSE 0 END,0) [InvD_Actual]
,ISNULL(CASE WHEN PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2,3) THEN [BMLD_Actual] ELSE 0 END,0) [BMLD_Actual]
,ISNULL(CASE WHEN PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2,3) THEN [InvN_Actual] ELSE 0 END,0) [InvN_Actual]
,ISNULL(CASE WHEN PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2,3) THEN [BMLN_Actual] ELSE 0 END,0) [BMLN_Actual]
,a.IncludeInTotal

FROM #FilteredParentChainBySuperRegion pc
JOIN #KPI_GPGAccountAssignments a
ON pc.ParentChainID = a.ParentChainID AND pc.SuperRegionID = a.SuperRegionID AND pc.RegionID = a.RegionID
LEFT JOIN [dbo].[GPG_KPIPulseData] k
ON pc.ParentChainID = k.ParentChainID AND pc.SuperRegionID = k.SuperRegionID AND pc.RegionID = k.RegionID
LEFT JOIN #KPI_GPGResource lrm
ON RTRIM(LTRIM(a.LeadRM)) = RTRIM(LTRIM(lrm.ResourceAlias))
WHERE a.IncludeInTotal = 1

UNION ALL

--RM    
SELECT 
7 RoleID
,ISNULL(rm.ResourceName,'Unassigned') ResourceName
,pc.*
,[AsOfBookingDate]
,[QTDCyActualNRN]
,[QTDCyActualRMD]
,CASE WHEN ISNULL([QTDPlanNRN],0)=0 THEN [QTDCyActualNRN] ELSE [QTDPlanNRN] END [QTDPlanNRN]
,CASE WHEN ISNULL([QTDPlanRMD],0)=0 THEN [QTDCyActualRMD] ELSE [QTDPlanRMD] END [QTDPlanRMD]
,[QTDLyActualNRN]
,[QTDLyActualRMD]
,ISNULL(Acquisitions_Targets,0) Acquisitions_Targets
,ISNULL(Acquisitions_Actual,0) Acquisitions_Actual
,ISNULL(CASE WHEN PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2,3) THEN RateLose_Targets ELSE 0 END,0) RateLose_Targets
,ISNULL(CASE WHEN PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2,3) THEN InvLose_Targets ELSE 0 END,0) InvLose_Targets
,ISNULL(CASE WHEN PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2,3) THEN [InvD_Actual] ELSE 0 END,0) [InvD_Actual]
,ISNULL(CASE WHEN PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2,3) THEN [BMLD_Actual] ELSE 0 END,0) [BMLD_Actual]
,ISNULL(CASE WHEN PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2,3) THEN [InvN_Actual] ELSE 0 END,0) [InvN_Actual]
,ISNULL(CASE WHEN PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2,3) THEN [BMLN_Actual] ELSE 0 END,0) [BMLN_Actual]
,a.IncludeInTotal

FROM #FilteredParentChainBySuperRegion pc
JOIN
( SELECT a.* FROM  #KPI_GPGAccountAssignments  a
	LEFT JOIN #IncludeInTotal i ON a.ParentChainID = i.ParentChainID AND a.SuperRegionID = i.SuperRegionID AND a.ReveneManager = i.ReveneManager
	WHERE i.ReveneManager IS NULL
 UNION
 SELECT * FROM #IncludeInTotal) a
ON pc.ParentChainID = a.ParentChainID AND pc.SuperRegionID = a.SuperRegionID AND pc.RegionID = a.RegionID
LEFT JOIN [dbo].[GPG_KPIPulseData] k
ON pc.ParentChainID = k.ParentChainID AND pc.SuperRegionID = k.SuperRegionID AND pc.RegionID = k.RegionID
LEFT JOIN #KPI_GPGResource rm
ON a.ReveneManager = rm.ResourceAlias

UNION ALL

--CM    
SELECT 
ISNULL(rm.RoleID,17) RoleID
,ISNULL(rm.ResourceName,'Unassigned') ResourceName
,pc.*
,[AsOfBookingDate]
,[QTDCyActualNRN]
,[QTDCyActualRMD]
,CASE WHEN ISNULL([QTDPlanNRN],0)=0 THEN [QTDCyActualNRN] ELSE [QTDPlanNRN] END [QTDPlanNRN]
,CASE WHEN ISNULL([QTDPlanRMD],0)=0 THEN [QTDCyActualRMD] ELSE [QTDPlanRMD] END [QTDPlanRMD]
,[QTDLyActualNRN]
,[QTDLyActualRMD]
,ISNULL(Acquisitions_Targets,0) Acquisitions_Targets
,ISNULL(Acquisitions_Actual,0) Acquisitions_Actual
,ISNULL(CASE WHEN PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2,3) THEN RateLose_Targets ELSE 0 END,0) RateLose_Targets
,ISNULL(CASE WHEN PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2,3) THEN InvLose_Targets ELSE 0 END,0) InvLose_Targets
,ISNULL(CASE WHEN PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2,3) THEN [InvD_Actual] ELSE 0 END,0) [InvD_Actual]
,ISNULL(CASE WHEN PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2,3) THEN [BMLD_Actual] ELSE 0 END,0) [BMLD_Actual]
,ISNULL(CASE WHEN PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2,3) THEN [InvN_Actual] ELSE 0 END,0) [InvN_Actual]
,ISNULL(CASE WHEN PROPERTY_PARNT_CHAIN_ACCT_TYP_ID IN (1,2,3) THEN [BMLN_Actual] ELSE 0 END,0) [BMLN_Actual]
,a.IncludeInTotal

FROM #FilteredParentChainBySuperRegion pc
JOIN #KPI_GPGAccountAssignments a
ON pc.ParentChainID = a.ParentChainID AND pc.SuperRegionID = a.SuperRegionID AND pc.RegionID = a.RegionID
LEFT JOIN [dbo].[GPG_KPIPulseData] k
ON pc.ParentChainID = k.ParentChainID AND pc.SuperRegionID = k.SuperRegionID AND pc.RegionID = k.RegionID
LEFT JOIN #KPI_GPGResource rm
ON a.ConnectivityManager = rm.ResourceAlias
WHERE a.IncludeInTotal = 1
ORDER BY 1
