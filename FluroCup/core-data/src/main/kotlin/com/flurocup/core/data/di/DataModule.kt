package com.flurocup.core.data.di

import android.content.Context
import androidx.room.Room
import com.flurocup.core.data.db.FluroDatabase
import com.flurocup.core.data.db.ProjectDao
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object DataModule {
    @Provides
    @Singleton
    fun provideDatabase(@ApplicationContext context: Context): FluroDatabase =
        Room.databaseBuilder(context, FluroDatabase::class.java, "flurocup.db").build()

    @Provides
    fun provideProjectDao(db: FluroDatabase): ProjectDao = db.projectDao()
}
