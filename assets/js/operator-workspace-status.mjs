export const OPERATOR_WORKSPACE_OCCUPIED_MESSAGE = "Multi-Screen is actief in een ander venster";

export function createOperatorWorkspaceStatusPresenter(statusElement) {
  return (state)=>{
    const occupied = state === "occupied";
    statusElement.hidden = !occupied;
    statusElement.textContent = occupied ? OPERATOR_WORKSPACE_OCCUPIED_MESSAGE : "";
  };
}