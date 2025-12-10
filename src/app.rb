require 'sinatra'
require 'mongo'

# Configuración de red
set :bind, '0.0.0.0'
set :port, 3000

# Conexión a MongoDB
client = Mongo::Client.new('mongodb://mongodb:27017/plataforma_cursos')
cursos_col = client[:cursos]

# RUTA 1: Ver cursos y mostrar formulario
get '/' do
  # Obtener lista actual de la base de datos
  lista_html = cursos_col.find.map do |curso|
    "<li><b>#{curso[:titulo]}</b> - #{curso[:duracion]} (#{curso[:precio]})</li>"
  end.join

  # Renderizar HTML simple
  "
  <div style='font-family: sans-serif; max-width: 600px; margin: 20px auto;'>
    <h1>🎓 Plataforma de Cursos</h1>
    
    <h3>Listado Disponible:</h3>
    <ul>#{lista_html.empty? ? '<li><i>No hay cursos todavía</i></li>' : lista_html}</ul>

    <hr style='margin: 30px 0;'>

    <h3>➕ Añadir Nuevo Curso:</h3>
    <form action='/nuevo' method='POST' style='display: flex; flex-direction: column; gap: 10px;'>
      <input type='text' name='titulo' placeholder='Nombre del curso' required style='padding: 8px;'>
      <input type='text' name='duracion' placeholder='Duración (ej: 10h)' required style='padding: 8px;'>
      <input type='text' name='precio' placeholder='Precio (ej: 15€)' required style='padding: 8px;'>
      <button type='submit' style='padding: 10px; background: #28a745; color: white; border: none; cursor: pointer;'>
        Guardar Curso
      </button>
    </form>
  </div>
  "
end

# RUTA 2: Recibir los datos del formulario y guardar
post '/nuevo' do
  nuevo_curso = {
    titulo: params[:titulo],
    duracion: params[:duracion],
    precio: params[:precio]
  }
  
  cursos_col.insert_one(nuevo_curso)
  
  # Recargar la página principal para ver el cambio
  redirect '/'
end