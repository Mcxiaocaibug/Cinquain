use axum::{Router, extract::State, response::IntoResponse, routing::get};

use crate::{WebError, template};

pub(crate) fn build() -> Router<crate::State> {
	Router::new()
		.route("/", get(index))
		.route("/support", get(support))
		.route("/_continuwuity/", get(index))
		.route("/_continuwuity/support", get(support))
}

async fn index(State(services): State<crate::State>) -> Result<impl IntoResponse, WebError> {
	template! {
		struct Index<'a> use "index.html.j2" {
			server_name: &'a str,
			first_run: bool,
			bootstrap_required: bool,
			support_email: Option<String>
		}
	}

	Ok(Index::new(
		&services,
		services.globals.server_name().as_str(),
		services.firstrun.is_first_run(),
		services.firstrun.bootstrap_required(),
		services.config.well_known.support_email.clone(),
	)
	.into_response())
}

async fn support(State(services): State<crate::State>) -> Result<impl IntoResponse, WebError> {
	template! {
		struct Support<'a> use "support.html.j2" {
			server_name: &'a str,
			first_run: bool,
			bootstrap_required: bool,
			support_email: Option<String>
		}
	}

	Ok(Support::new(
		&services,
		services.globals.server_name().as_str(),
		services.firstrun.is_first_run(),
		services.firstrun.bootstrap_required(),
		services.config.well_known.support_email.clone(),
	)
	.into_response())
}
