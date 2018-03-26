USE [SB_PA_Margaret]
GO

/****** Object:  StoredProcedure [dbo].[CREATE_ACTIVE_LOAN_TBL]    Script Date: 2/2/2018 9:47:44 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO




/*========================================= Active Loan Population -- need to match with month end loan table============================================*/
CREATE PROCEDURE [dbo].[CREATE_ACTIVE_LOAN_TBL] @DATE_KEY INT 
AS

BEGIN 

--DECLARE @DATE_KEY INT = 20171130;

UPDATE [SB_PA_Margaret].[FRB\mlan].[TBL_LOAN_STATUS] 
SET [CURRENT] = 'N'
FROM [SB_PA_Margaret].[FRB\mlan].[TBL_LOAN_STATUS] 
WHERE DATE_KEY = @DATE_KEY;

DROP TABLE #ACCT_INC;

WITH 
--------------------------AFS_INC-----------------------------------------------
COUNT_BY_TRANCHE AS (
	SELECT L.TRANCHE_ACCT_NBR
		 , SUM(IIF(L.PROC_TYPE LIKE '5%', 1, 0)) AS CURRENT_OBL_COUNT
		 , count(*) as OBL_COUNT
	FROM [RDM_LOAN].[ADJ].[T_FACT_LOAN_EOM] EOM
		LEFT JOIN [RDM_LOAN].[ADJ].[T_DIM_LOAN] L ON EOM.LN_KEY=L.LN_KEY
	WHERE EOM.DATE_KEY=@DATE_KEY
		AND EOM.SRC_TYPE_CD='AFS'
	GROUP BY TRANCHE_ACCT_NBR
)

, TRANCHE_COMMITMENT AS (
	SELECT L.TRANCHE_ACCT_NBR
		 , SUM(EOM.COMMITMENT) CAL_TRANCHE_COMMITMENT
	FROM [RDM_LOAN].[ADJ].[T_FACT_LOAN_EOM] EOM
		LEFT JOIN [RDM_LOAN].[ADJ].[T_DIM_LOAN] L ON EOM.LN_KEY=L.LN_KEY
	WHERE EOM.DATE_KEY=@DATE_KEY
		AND EOM.SRC_TYPE_CD='AFS'
	GROUP BY TRANCHE_ACCT_NBR
)

, AFS_INC AS (
	SELECT EOM.ACCT_NBR, EOM.[LN_KEY], EOM.[DATE_KEY], EOM.[PROD_DT], EOM.SRC_TYPE_CD, EOM.[HIERARCHY_LEVEL], EOM.[NEW_LOAN_FLAG]
		 , IIF(L.PROC_TYPE LIKE '5_55', IIF(PR.SRC_PROD_CD<>'132026' AND C.OBL_COUNT=2, 'Y', NULL), NULL) AS CURR_FUT_1_1_FLAG
	FROM [RDM_LOAN].[ADJ].[T_FACT_LOAN_EOM] EOM
		LEFT JOIN [RDM_LOAN].[ADJ].[T_DIM_LOAN] L ON EOM.LN_KEY=L.LN_KEY
		LEFT JOIN [RDM_LOAN].[ADJ].[T_FACT_LOAN_EOM] EOM2 ON L.TRANCHE_ACCT_NBR=EOM2.ACCT_NBR AND EOM2.DATE_KEY=@DATE_KEY
		LEFT JOIN [RDM_LOAN].[ADJ].[T_DIM_LOAN_PRODUCT] PR ON EOM2.LN_PRODUCT_KEY=PR.LN_PRODUCT_KEY
		LEFT JOIN COUNT_BY_TRANCHE C ON L.TRANCHE_ACCT_NBR=C.TRANCHE_ACCT_NBR
		LEFT JOIN TRANCHE_COMMITMENT TC	ON L.TRANCHE_ACCT_NBR=TC.TRANCHE_ACCT_NBR
	WHERE EOM.DATE_KEY=@DATE_KEY
		AND EOM.SRC_TYPE_CD='AFS'
		AND TC.CAL_TRANCHE_COMMITMENT<>0
		AND L.PROC_TYPE NOT LIKE '_[34679]__'
		AND IIF(L.PROC_TYPE LIKE '[03]_12', 1, IIF(L.PROC_TYPE LIKE '[0123]_1_', 0, IIF(L.PROC_TYPE LIKE '[23]%', 0, 1)))=1
		AND (		EOM.CURRENT_BAL<>0
				OR	EOM.FUTURE_BAL<>0
				OR	EOM.HIERARCHY_LEVEL=0
				OR	(L.PROC_TYPE LIKE '5%' AND C.CURRENT_OBL_COUNT=1)
			)
)

---------------------------OSI_INC-----------------------------------------------

, OSI_INC AS (
	SELECT EOM.ACCT_NBR, NULL AS CURR_FUT_1_1_FLAG
	, EOM.[LN_KEY], EOM.[DATE_KEY], EOM.[PROD_DT], EOM.SRC_TYPE_CD, EOM.[HIERARCHY_LEVEL], EOM.[NEW_LOAN_FLAG]
	FROM [RDM_LOAN].[ADJ].[T_FACT_LOAN_EOM] EOM
		LEFT JOIN [RDM_LOAN].[ADJ].[T_DIM_LOAN_STATUS] S ON EOM.LN_STATUS_KEY=S.LN_STATUS_KEY
	WHERE EOM.DATE_KEY=@DATE_KEY
		AND EOM.SRC_TYPE_CD IN ('IL', 'ML')
		AND S.STATUS_CD!=2
--		AND IIF(EOM.SRC_TYPE_CD='ML', IIF(EOM.NET_BOOK_BAL=0, 0, 1) /*REMOVE ML LOAN WITH NBB 0, WHICH IS A FULL CHARGEOFF BUT NOT YET CONVERTED INTO REO */, 1)=1
)

------------------------ALL_LOAN_INC-----------------------------------------------
, ACCT_INC AS (
	SELECT ACCT_NBR, LN_KEY, [DATE_KEY], [PROD_DT], SRC_TYPE_CD, [HIERARCHY_LEVEL], [NEW_LOAN_FLAG], CURR_FUT_1_1_FLAG 
	FROM AFS_INC
	UNION 
	SELECT ACCT_NBR, LN_KEY, [DATE_KEY], [PROD_DT], SRC_TYPE_CD, [HIERARCHY_LEVEL], [NEW_LOAN_FLAG], CURR_FUT_1_1_FLAG 
	FROM OSI_INC
)

SELECT * INTO #ACCT_INC FROM ACCT_INC;

--====================INSERT ACTIVE LOAN INTO LOCAL TABLE IN [SB_PA_Margaret].[FRB\mlan]========================================

INSERT INTO [SB_PA_Margaret].[FRB\mlan].[TBL_LOAN_STATUS] (
	   [LN_KEY]
      ,[DATE_KEY]
	  ,[PROD_DT]
      ,[SRC_TYPE_CD]
      ,[ACCT_NBR]
      ,[TRANCHE_ACCT_NBR]
	  ,[EAGLE_FLAG]
      ,[HIERARCHY_LEVEL]
      ,[NEW_LOAN_FLAG]
      ,[CURRENT_FLAG]
      ,[CURR_FUT_1_1_FLAG]
      ,[BISYS_NBR_FMT]
      ,[BISYS_NBR_MID]
	  ,[POWERLENDER_ACCT_NBR]
	  ,[LOANFACT_ACCT_NBR]
	  ,[CREMF_ACCT_NBR]
	  ,[CURRENT]
      ,[INSERT_DATETIME]) 

SELECT  A.LN_KEY
	   ,A.[DATE_KEY]
	   ,A.[PROD_DT]
	   ,A.SRC_TYPE_CD
	   ,A.ACCT_NBR
	   ,L.[TRANCHE_ACCT_NBR]
	   ,L.[EAGLE_LENDING_FLAG]
	   ,A.[HIERARCHY_LEVEL]
	   ,A.[NEW_LOAN_FLAG]
	   ,L.[CURRENT_FLAG]
	   ,A.CURR_FUT_1_1_FLAG 
	   ,L.[BISYS_NBR_FMT]
	   ,L.[BISYS_NBR_MID]
	   ,CASE 
			WHEN EMP.[Customer_key] IS NULL THEN PL.[A304_CustomerKey] 
			ELSE EMP.[Customer_key]
		END AS PL_ACCT_NBR
	   ,PLF.[Loan_Key]
	   ,IP.[BisysNo_Short]
	   ,'Y' AS [CURRENT]
	   ,GETDATE() AS INSERT_DATETIME 

FROM #ACCT_INC A

LEFT JOIN [RDM_LOAN].[ADJ].[T_DIM_LOAN] L ON A.LN_KEY=L.LN_KEY


  LEFT JOIN [PLProd].[dbo].[vw_powerlender] PL
	ON PL.A304_CustomerKey =
		CASE 
		WHEN SUBSTRING(L.Bisys_Nbr_Fmt,4,1)='7'
			 THEN '0' + SUBSTRING(L.Bisys_Nbr_Fmt,4,6) + RIGHT(L.Bisys_Nbr_Fmt,1)
		ELSE 
			 RIGHT(L.Bisys_Nbr_Fmt,8)
		END
  LEFT JOIN [PLProd].[dbo].[vw_LoanFacts] PLF
	ON PLF.Loan_Key =
		CASE 
		WHEN SUBSTRING(L.Bisys_Nbr_Fmt,4,1)='7'
			 THEN LEFT(L.Bisys_Nbr_Fmt,2) + '-0' + SUBSTRING(L.Bisys_Nbr_Fmt,4,6) + RIGHT(L.Bisys_Nbr_Fmt,1)
		ELSE 
			 L.Bisys_Nbr_Fmt
		END
  LEFT JOIN [PLProd_EMPLOYEE].[dbo].[VW_LOAN_FACT_EMP_CUSO] EMP
	ON EMP.[Customer_key] =
		CASE 
		WHEN SUBSTRING(L.Bisys_Nbr_Fmt,4,1)='7'
			 THEN '0' + SUBSTRING(L.Bisys_Nbr_Fmt,4,6) + RIGHT(L.Bisys_Nbr_Fmt,1)
		ELSE 
			 RIGHT(L.Bisys_Nbr_Fmt,8)
		END
  LEFT JOIN [CREMF].[dbo].[CRE_Collateral] IP
    ON right(L.Bisys_Nbr_Fmt,8)=IP.[BisysNo_Short] 


END
















GO

