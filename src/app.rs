use iced::{pure::{widget::*, Application}, Command};

use self::{
    message::Message,
};

mod message;

pub struct Levent {}

impl Application for Levent {
    type Executor = iced::executor::Default;

    type Message = Message;

    type Flags = ();

    fn new(flags: Self::Flags) -> (Self, Command<Self::Message>) {
        (Self {}, Command::none())
    }

    fn title(&self) -> String {
        "levent".into()
    }

    fn update(&mut self, message: Self::Message) -> Command<Self::Message> {
        match message {

        }
    }

    fn view(&self) -> iced::pure::Element<'_, Self::Message> {
        Text::new("aaaa").into()
    }
}