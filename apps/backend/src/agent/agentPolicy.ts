import { actionDefinitions, type ActionDefinition, type ActionContext } from "@cal-tracker/contracts";

const agentRunBlockedMutations = new Set([
  "create_usual_food",
  "update_usual_food",
  "delete_usual_food",
  "create_meal_template",
  "update_meal_template",
  "delete_meal_template",
  "correct_meal",
]);

export function filterToolsByPolicy(actions: ActionDefinition[], context: ActionContext): ActionDefinition[] {
  return actions.filter((action) => {
    // 1. Scope check
    if (!context.scopes.includes(action.permissionScope)) return false;
    // Usual ingredients/meals must be saved only by reviewed direct UI writes.
    if (agentRunBlockedMutations.has(action.id)) return false;
    return true;
  });
}
