import fc.maintenance.cli
import fc.manage.postgresql
import typer

app = typer.Typer()
app.add_typer(fc.maintenance.cli.app, name="maintenance")
app.add_typer(fc.manage.postgresql.app, name="postgresql")
