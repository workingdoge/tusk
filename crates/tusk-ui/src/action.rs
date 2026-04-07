use crate::app::ViewMode;

#[allow(dead_code)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum Direction {
    Forward,
    Backward,
}

#[allow(dead_code)]
#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) enum UiAction {
    Quit,
    Refresh,
    Ping,
    SwitchView(ViewMode),
    CycleView(Direction),
    MoveBoardSelection(isize),
    Claim(String),
    Launch(String, String),
    Finish(String),
    Inspect(String),
    ShowHelp,
    DismissOverlay,
}
