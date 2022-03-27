use iced::pure::Application;

mod app;

fn main() {
    app::Levent::run(iced::Settings::with_flags(())).unwrap();
}