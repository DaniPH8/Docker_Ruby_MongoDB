require 'sinatra'
require 'mongo'

set :bind, '0.0.0.0'
set :port, 3000

# Conexión a MongoDB
client = Mongo::Client.new('mongodb://mongodb:27017/plataforma_cursos')
cursos_col = client[:cursos]

# --- R (READ): Listar cursos ---
get '/' do
  lista_html = cursos_col.find.map do |curso|
    id = curso[:_id].to_s
    "
    <li style='margin-bottom: 10px; padding: 10px; border: 1px solid #ddd; display: flex; justify-content: space-between; align-items: center;'>
      <span><b>#{curso[:titulo]}</b> - #{curso[:duracion]} (#{curso[:precio]})</span>
      <div style='display: flex; gap: 5px;'>
        <a href='/editar/#{id}' style='text-decoration: none; padding: 5px 10px; background: #ffc107; color: black; border-radius: 4px;'>✏️ Editar</a>
        
        <form action='/borrar/#{id}' method='POST' style='margin: 0;' onsubmit=\"return confirm('⚠️ ¿Estás seguro de que quieres eliminar este curso permanentemente?');\">
          <button type='submit' style='padding: 5px 10px; background: #dc3545; color: white; border: none; border-radius: 4px; cursor: pointer;'>🗑️ Borrar</button>
        </form>
      </div>
    </li>
    "
  end.join

  "
  <div style='font-family: sans-serif; max-width: 800px; margin: 20px auto;'>
    <h1>🎓 Gestión de Cursos</h1>
    
    <h3>Listado:</h3>
    <ul style='list-style: none; padding: 0;'>#{lista_html.empty? ? '<li><i>No hay cursos</i></li>' : lista_html}</ul>

    <hr>

    <h3>➕ Crear Nuevo Curso:</h3>
    #{form_curso('/nuevo', 'Crear Curso')}
  </div>
  "
end

# --- C (CREATE) ---
post '/nuevo' do
  cursos_col.insert_one({
    titulo: params[:titulo],
    duracion: params[:duracion],
    precio: params[:precio]
  })
  redirect '/'
end

# --- U (UPDATE - Formulario) ---
get '/editar/:id' do
  id = BSON::ObjectId.from_string(params[:id])
  curso = cursos_col.find(_id: id).first

  "
  <div style='font-family: sans-serif; max-width: 600px; margin: 20px auto;'>
    <h1>✏️ Editar Curso</h1>
    #{form_curso("/actualizar/#{params[:id]}", 'Actualizar Curso', curso[:titulo], curso[:duracion], curso[:precio])}
    <br><a href='/'>Cancelar</a>
  </div>
  "
end

# --- U (UPDATE - Proceso) ---
post '/actualizar/:id' do
  id = BSON::ObjectId.from_string(params[:id])
  cursos_col.update_one({ _id: id }, { '$set' => {
    titulo: params[:titulo],
    duracion: params[:duracion],
    precio: params[:precio]
  }})
  redirect '/'
end

# --- D (DELETE) ---
post '/borrar/:id' do
  id = BSON::ObjectId.from_string(params[:id])
  cursos_col.delete_one(_id: id)
  redirect '/'
end

# --- HELPER HTML ---
def form_curso(accion, texto_boton, titulo='', duracion='', precio='')
  "
  <form action='#{accion}' method='POST' style='display: flex; flex-direction: column; gap: 10px; background: #f9f9f9; padding: 15px; border-radius: 5px;'>
    <input type='text' name='titulo' value='#{titulo}' placeholder='Nombre del curso' required style='padding: 8px;'>
    <input type='text' name='duracion' value='#{duracion}' placeholder='Duración (ej: 10h)' required style='padding: 8px;'>
    <input type='text' name='precio' value='#{precio}' placeholder='Precio (ej: 15€)' required style='padding: 8px;'>
    <button type='submit' style='padding: 10px; background: #28a745; color: white; border: none; cursor: pointer; font-weight: bold;'>
      #{texto_boton}
    </button>
  </form>
  "
end