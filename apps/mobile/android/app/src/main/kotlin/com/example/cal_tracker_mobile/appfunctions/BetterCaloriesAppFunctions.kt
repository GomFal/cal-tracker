package com.example.cal_tracker_mobile.appfunctions

import androidx.appfunctions.AppFunctionContext
import androidx.appfunctions.service.AppFunction

/**
 * Android AppFunctions exposed to Gemini and other system agents.
 *
 * Each function is intentionally thin: it forwards the request to Dart through
 * app_intents and Dart delegates to the existing BetterCalories backend action
 * executor. This keeps AppFunctions from duplicating nutrition logic.
 */
@Suppress("UNUSED_PARAMETER")
class BetterCaloriesAppFunctions {
    /**
     * Get calories and macro totals for a day in BetterCalories.
     *
     * @param appFunctionContext The context for this app function execution.
     * @param date Optional local date in yyyy-MM-dd format. Omit for today.
     */
    @AppFunction(isDescribedByKDoc = true)
    suspend fun getDailySummary(
        appFunctionContext: AppFunctionContext,
        date: String? = null,
    ): String = BetterCaloriesAppFunctionBridge.executeIntent(
        "app.bettercalories.GetDailySummary",
        paramsOf("date" to date),
    )

    /**
     * Get remaining calories and macros for a day in BetterCalories.
     *
     * @param appFunctionContext The context for this app function execution.
     * @param date Optional local date in yyyy-MM-dd format. Omit for today.
     */
    @AppFunction(isDescribedByKDoc = true)
    suspend fun getRemainingTargets(
        appFunctionContext: AppFunctionContext,
        date: String? = null,
    ): String = BetterCaloriesAppFunctionBridge.executeIntent(
        "app.bettercalories.GetRemainingTargets",
        paramsOf("date" to date),
    )

    /**
     * List recent committed meals from BetterCalories.
     *
     * @param appFunctionContext The context for this app function execution.
     * @param limit Optional maximum number of meals to return, from 1 to 100.
     */
    @AppFunction(isDescribedByKDoc = true)
    suspend fun getMealHistory(
        appFunctionContext: AppFunctionContext,
        limit: Int? = null,
    ): String = BetterCaloriesAppFunctionBridge.executeIntent(
        "app.bettercalories.GetMealHistory",
        paramsOf("limit" to limit),
    )

    /**
     * Search BetterCalories nutrition data and user foods.
     *
     * Use this when the user asks to look up nutrition facts rather than log a
     * meal.
     *
     * @param appFunctionContext The context for this app function execution.
     * @param query Food name, brand, or nutrition search text.
     * @param barcode Optional barcode value when available.
     */
    @AppFunction(isDescribedByKDoc = true)
    suspend fun searchNutritionDatabase(
        appFunctionContext: AppFunctionContext,
        query: String,
        barcode: String? = null,
    ): String = BetterCaloriesAppFunctionBridge.executeIntent(
        "app.bettercalories.SearchNutritionDatabase",
        paramsOf("query" to query, "barcode" to barcode),
    )

    /**
     * Create a BetterCalories meal proposal from natural-language food text.
     *
     * This returns a proposal or clarification data. It does not directly commit
     * a meal unless the backend/user settings explicitly allow that.
     *
     * @param appFunctionContext The context for this app function execution.
     * @param text Natural-language description of food and quantities.
     * @param occurredAt Optional UTC ISO-8601 consumed-at timestamp.
     */
    @AppFunction(isDescribedByKDoc = true)
    suspend fun proposeMealLog(
        appFunctionContext: AppFunctionContext,
        text: String,
        occurredAt: String? = null,
    ): String = BetterCaloriesAppFunctionBridge.executeIntent(
        "app.bettercalories.ProposeMealLog",
        paramsOf("text" to text, "occurredAt" to occurredAt),
    )

    /**
     * List the user's usual ingredients saved in BetterCalories.
     *
     * @param appFunctionContext The context for this app function execution.
     */
    @AppFunction(isDescribedByKDoc = true)
    suspend fun getUsualFoods(
        appFunctionContext: AppFunctionContext,
    ): String = BetterCaloriesAppFunctionBridge.executeIntent(
        "app.bettercalories.GetUsualFoods",
        emptyMap(),
    )

    /**
     * List the user's usual meal templates saved in BetterCalories.
     *
     * @param appFunctionContext The context for this app function execution.
     */
    @AppFunction(isDescribedByKDoc = true)
    suspend fun getUsualMeals(
        appFunctionContext: AppFunctionContext,
    ): String = BetterCaloriesAppFunctionBridge.executeIntent(
        "app.bettercalories.GetUsualMeals",
        emptyMap(),
    )

    /**
     * Ask the BetterCalories agent to interpret a nutrition or meal request.
     *
     * Use this when the system agent has natural-language instructions and wants
     * BetterCalories to choose the appropriate internal nutrition tool.
     *
     * @param appFunctionContext The context for this app function execution.
     * @param text Natural-language request for the BetterCalories agent.
     * @param activeProposalId Optional proposal id when revising an existing proposal.
     */
    @AppFunction(isDescribedByKDoc = true)
    suspend fun askBetterCalories(
        appFunctionContext: AppFunctionContext,
        text: String,
        activeProposalId: String? = null,
    ): String = BetterCaloriesAppFunctionBridge.executeIntent(
        "app.bettercalories.AskBetterCalories",
        paramsOf("text" to text, "activeProposalId" to activeProposalId),
    )

    /**
     * Execute a whitelisted BetterCalories nutrition action by id.
     *
     * This is an escape hatch for system agents that already know the action id.
     * Only read, draft, and meal-proposal actions are allowed. Destructive or
     * direct write actions are blocked.
     *
     * @param appFunctionContext The context for this app function execution.
     * @param actionId Internal BetterCalories action id to execute.
     * @param inputJson Optional JSON object string with action input.
     */
    @AppFunction(isDescribedByKDoc = true)
    suspend fun executeNutritionAction(
        appFunctionContext: AppFunctionContext,
        actionId: String,
        inputJson: String? = null,
    ): String = BetterCaloriesAppFunctionBridge.executeIntent(
        "app.bettercalories.ExecuteNutritionAction",
        paramsOf("actionId" to actionId, "inputJson" to inputJson),
    )
}

private fun paramsOf(vararg values: Pair<String, Any?>): Map<String, Any?> =
    values.mapNotNull { (key, value) -> value?.let { key to it } }.toMap()
