<?php

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;
use App\Http\Controllers\AuthController;
use App\Http\Controllers\S3Controller;
use App\Http\Controllers\ProjectController;
use App\Http\Controllers\ModelController;
use App\Http\Controllers\SnapshotController;

/*
|--------------------------------------------------------------------------
| API Routes
|--------------------------------------------------------------------------
|
| Here is where you can register API routes for your application. These
| routes are loaded by the RouteServiceProvider within a group which
| is assigned the "api" middleware group. Enjoy building your API!
|
*/

Route::middleware('auth:sanctum')->get('/user', function (Request $request) {
    return $request->user();
});
Route::post('register', [AuthController::class, 'register']);
Route::post('login', [AuthController::class, 'login']);


Route::group(['middleware' => ['auth:sanctum']], function () {
    Route::get('logout', [AuthController::class, 'logout']);
    Route::resource('project', ProjectController::class);
    Route::post('project/list', [ProjectController::class, 'list']);
    Route::post('project/delete', [ProjectController::class, 'delete']);
    Route::resource('snapshot', SnapshotController::class);
    Route::post('upload', [ S3Controller::class, 'uploadFile' ]);
    Route::post('file/read', [ S3Controller::class, 'readFile' ]);
    Route::post('file/list', [ S3Controller::class, 'listFile' ]);
    Route::post('file/update', [ S3Controller::class, 'updateFile' ]);
    Route::post('file/create', [ S3Controller::class, 'createFile' ]);
    Route::delete('file/{id}', [ S3Controller::class, 'deleteFile' ]);
    Route::post('mkdir', [ S3Controller::class, 'mkdir' ]);
    Route::post('simulate', [ ModelController::class, 'simulate' ]);
    Route::get('simulate/latest/{id}', [ ModelController::class, 'simulateLatest' ]);
    Route::get('simulate/download/{id}', [ ModelController::class, 'simulateDownload' ]);
    Route::get('user/{id}', [ AuthController::class, 'userinfo' ]);
    Route::post('user/update/{id}', [ AuthController::class, 'update' ]);
});
