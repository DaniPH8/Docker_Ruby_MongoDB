require 'sinatra'
require 'mongo'
require 'json'
require 'fileutils'

set :bind, '0.0.0.0'
set :port, 3000

# Configuración de carpeta pública para imágenes
set :public_folder, File.join(File.dirname(__FILE__), '../public')

# Conexión MongoDB
client = Mongo::Client.new('mongodb://mongodb:27017/plataforma_cursos')
cursos_col = client[:cursos]

# --- VISTA PRINCIPAL ---
get '/' do
  cards_html = cursos_col.find.map do |curso|
    id = curso[:_id].to_s
    img_path = curso[:imagen] ? "/uploads/#{curso[:imagen]}" : "https://via.placeholder.com/300x200?text=Sin+Imagen"
    
    "
    <div class='col-md-4 mb-4'>
      <div class='card h-100 shadow-sm'>
        <div style='height: 200px; overflow: hidden; background: #eee;'>
          <img src='#{img_path}' class='card-img-top' style='width: 100%; height: 100%; object-fit: cover;' alt='Curso'>
        </div>
        <div class='card-body'>
          <h5 class='card-title'>#{curso[:titulo]}</h5>
          <p class='card-text text-muted'>⏱️ #{curso[:duracion]} | 🏷️ #{curso[:precio]}</p>
        </div>
        <div class='card-footer bg-white border-top-0 d-flex justify-content-between'>
          <a href='/editar/#{id}' class='btn btn-outline-warning btn-sm'>✏️ Editar</a>
          <form action='/borrar/#{id}' method='POST' style='margin:0;' onsubmit=\"return confirm('¿Borrar curso?');\">
            <button type='submit' class='btn btn-outline-danger btn-sm'>🗑️ Borrar</button>
          </form>
        </div>
      </div>
    </div>
    "
  end.join

  layout(
    "
    <div class='p-5 mb-4 bg-dark text-white rounded-3' style='background: linear-gradient(to right, #2c3e50, #4ca1af);'>
      <div class='container-fluid py-3'>
        <h1 class='display-5 fw-bold'>Mis Cursos Online</h1>
        <p class='fs-4'>Catálogo gestionado con Ruby, Mongo y Git.</p>
        <a href='#form-crear' class='btn btn-light btn-lg'>+ Subir Curso</a>
      </div>
    </div>

    <div class='container'>
      <h3 class='mb-4 border-bottom pb-2'>📚 Catálogo</h3>
      <div class='row'>
        #{cards_html.empty? ? '<div class="alert alert-warning">No hay cursos. Añade uno con foto abajo.</div>' : cards_html}
      </div>
    </div>

    <div class='container mt-5 mb-5' id='form-crear'>
      <div class='card shadow'>
        <div class='card-header bg-primary text-white'>➕ Nuevo Curso</div>
        <div class='card-body'>
          #{form_curso('/nuevo', 'Guardar Curso')}
        </div>
      </div>
    </div>
    "
  )
end

# --- GIT PUSH ---
post '/subir-git' do
  begin
    datos = cursos_col.find.to_a
    datos.each { |d| d[:_id] = d[:_id].to_s }
    File.write('backup_cursos.json', JSON.pretty_generate(datos))

    cmd = "git add . && git commit -m 'Backup completo' && git push origin main 2>&1"
    output = `#{cmd}`
    
    if $?.success?
      layout("<div class='text-center mt-5'><h1 class='text-success'>✅ Backup Exitoso</h1><p>Código, BD e imágenes subidas.</p><a href='/' class='btn btn-primary'>Volver</a></div>")
    else
      layout("<div class='container mt-5 alert alert-danger'><pre>#{output}</pre><a href='/' class='btn btn-secondary'>Volver</a></div>")
    end
  rescue => e
    "Error: #{e.message}"
  end
end

# --- LOGICA DE IMAGEN ---
def guardar_imagen(params_imagen)
  return nil unless params_imagen
  filename = params_imagen[:filename]
  path = File.join(File.dirname(__FILE__), '../public/uploads', filename)
  File.open(path, 'wb') { |f| f.write(params_imagen[:tempfile].read) }
  filename
end

# --- CRUD ---
post '/nuevo' do
  nombre_imagen = guardar_imagen(params[:imagen])
  cursos_col.insert_one({ titulo: params[:titulo], duracion: params[:duracion], precio: params[:precio], imagen: nombre_imagen })
  redirect '/'
end

post '/actualizar/:id' do
  id = BSON::ObjectId.from_string(params[:id])
  update_data = { titulo: params[:titulo], duracion: params[:duracion], precio: params[:precio] }
  if params[:imagen]
    nombre_imagen = guardar_imagen(params[:imagen])
    update_data[:imagen] = nombre_imagen
  end
  cursos_col.update_one({ _id: id }, { '$set' => update_data })
  redirect '/'
end

post '/borrar/:id' do
  cursos_col.delete_one(_id: BSON::ObjectId.from_string(params[:id]))
  redirect '/'
end

get '/editar/:id' do
  id = BSON::ObjectId.from_string(params[:id])
  curso = cursos_col.find(_id: id).first
  layout("
    <div class='container mt-5' style='max-width: 600px;'>
      <div class='card'>
        <div class='card-header bg-warning'>✏️ Editar Curso</div>
        <div class='card-body'>
          #{form_curso("/actualizar/#{params[:id]}", 'Actualizar', curso[:titulo], curso[:duracion], curso[:precio], true)}
          <a href='/' class='btn btn-link mt-3'>Cancelar</a>
        </div>
      </div>
    </div>
  ")
end

# --- LAYOUT Y FORMULARIO ---
def layout(contenido)
  "<!DOCTYPE html>
  <html lang='es'>
  <head>
    <meta charset='UTF-8'><meta name='viewport' content='width=device-width, initial-scale=1'>
    <title>Cursos Online</title>
    <link href='https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css' rel='stylesheet'>
  </head>
  <body class='bg-light'>
    <nav class='navbar navbar-expand-lg navbar-dark bg-dark shadow-sm'>
      <div class='container'>
        <a class='navbar-brand' href='/'>📷 Cursos online</a>
        <form action='/subir-git' method='POST' class='d-flex m-0'>
          <button type='submit' class='btn btn-outline-light btn-sm'>☁️ Push Git</button>
        </form>
      </div>
    </nav>
    #{contenido}
  </body></html>"
end

def form_curso(accion, btn_txt, tit='', dur='', pre='', es_edicion=false)
  nota_imagen = es_edicion ? "<small class='text-muted'>Deja vacío para mantener la imagen actual</small>" : ""
  "<form action='#{accion}' method='POST' enctype='multipart/form-data'>
    <div class='mb-3'><label class='form-label'>Título</label><input type='text' name='titulo' value='#{tit}' class='form-control' required></div>
    <div class='row'>
      <div class='col-md-6 mb-3'><label class='form-label'>Duración</label><input type='text' name='duracion' value='#{dur}' class='form-control' required></div>
      <div class='col-md-6 mb-3'><label class='form-label'>Precio</label><input type='text' name='precio' value='#{pre}' class='form-control' required></div>
    </div>
    <div class='mb-3'><label class='form-label'>Imagen</label><input type='file' name='imagen' class='form-control' accept='image/*'>#{nota_imagen}</div>
    <button type='submit' class='btn btn-success w-100'>#{btn_txt}</button>
  </form>"
end