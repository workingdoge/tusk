use std::sync::mpsc::{self, Receiver, Sender};
use std::thread;

use crate::protocol::ProtocolClient;
use crate::types::{BoardStatus, OperatorSnapshot, ReceiptsStatus, TrackerStatus};

type FetchResult<T> = std::result::Result<T, String>;

#[derive(Clone, Copy, Debug, Default)]
pub(crate) struct RefreshSet {
    pub(crate) home: bool,
    pub(crate) tracker: bool,
    pub(crate) board: bool,
    pub(crate) receipts: bool,
}

impl RefreshSet {
    pub(crate) fn all() -> Self {
        Self {
            home: true,
            tracker: true,
            board: true,
            receipts: true,
        }
    }

    pub(crate) fn any(self) -> bool {
        self.home || self.tracker || self.board || self.receipts
    }

    pub(crate) fn merge(self, other: Self) -> Self {
        Self {
            home: self.home || other.home,
            tracker: self.tracker || other.tracker,
            board: self.board || other.board,
            receipts: self.receipts || other.receipts,
        }
    }

    pub(crate) fn describe(self) -> String {
        let mut names = Vec::new();
        if self.home {
            names.push("home");
        }
        if self.tracker {
            names.push("tracker");
        }
        if self.board {
            names.push("board");
        }
        if self.receipts {
            names.push("receipts");
        }
        names.join(", ")
    }
}

#[derive(Debug)]
pub(crate) enum RefreshUpdate {
    Home(FetchResult<OperatorSnapshot>),
    Tracker(FetchResult<TrackerStatus>),
    Board(FetchResult<BoardStatus>),
    Receipts(FetchResult<ReceiptsStatus>),
}

#[derive(Debug)]
pub(crate) struct RefreshWorker {
    request_tx: Sender<RefreshSet>,
    response_rx: Receiver<RefreshUpdate>,
}

impl RefreshWorker {
    pub(crate) fn start(client: ProtocolClient) -> Self {
        let (request_tx, request_rx) = mpsc::channel::<RefreshSet>();
        let (response_tx, response_rx) = mpsc::channel::<RefreshUpdate>();

        thread::spawn(move || run_worker(client, request_rx, response_tx));

        Self {
            request_tx,
            response_rx,
        }
    }

    pub(crate) fn request(&self, refresh_set: RefreshSet) -> Result<(), String> {
        if !refresh_set.any() {
            return Ok(());
        }

        self.request_tx
            .send(refresh_set)
            .map_err(|_| "refresh worker is unavailable".to_owned())
    }

    pub(crate) fn drain(&self) -> Vec<RefreshUpdate> {
        let mut updates = Vec::new();
        while let Ok(update) = self.response_rx.try_recv() {
            updates.push(update);
        }
        updates
    }
}

fn run_worker(
    client: ProtocolClient,
    request_rx: Receiver<RefreshSet>,
    response_tx: Sender<RefreshUpdate>,
) {
    while let Ok(mut refresh_set) = request_rx.recv() {
        while let Ok(extra) = request_rx.try_recv() {
            refresh_set = refresh_set.merge(extra);
        }

        if refresh_set.home
            && response_tx
                .send(RefreshUpdate::Home(fetch_home(&client)))
                .is_err()
        {
            break;
        }

        if refresh_set.tracker
            && response_tx
                .send(RefreshUpdate::Tracker(fetch_tracker(&client)))
                .is_err()
        {
            break;
        }

        if refresh_set.board
            && response_tx
                .send(RefreshUpdate::Board(fetch_board(&client)))
                .is_err()
        {
            break;
        }

        if refresh_set.receipts
            && response_tx
                .send(RefreshUpdate::Receipts(fetch_receipts(&client)))
                .is_err()
        {
            break;
        }
    }
}

fn fetch_home(client: &ProtocolClient) -> FetchResult<OperatorSnapshot> {
    client.operator_snapshot().map_err(format_error)
}

fn fetch_tracker(client: &ProtocolClient) -> FetchResult<TrackerStatus> {
    client.tracker_status().map_err(format_error)
}

fn fetch_board(client: &ProtocolClient) -> FetchResult<BoardStatus> {
    client.board_status().map_err(format_error)
}

fn fetch_receipts(client: &ProtocolClient) -> FetchResult<ReceiptsStatus> {
    client.receipts_status().map_err(format_error)
}

fn format_error(error: anyhow::Error) -> String {
    format!("{error:#}")
}
